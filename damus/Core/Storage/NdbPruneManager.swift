//
//  NdbPruneManager.swift
//  damus
//
//  Runs size-budgeted prunes in the background while the app is live, and
//  leaves the result staged for the next launch to swap in. The database in use
//  is never touched.
//

import Foundation

/// Watches the database against the user's space budget and, when it grows past
/// it, prunes a copy into a staging directory for the next launch.
///
/// The prune itself is what makes this viable at runtime: `ndb_prune` opens its
/// source transaction with raw LMDB rather than `ndb_begin_query`, so its
/// multi-minute read is invisible to the DEBUG long-lived-query watchdog, and it
/// writes somewhere else entirely, so the live database keeps taking writes
/// throughout.
///
/// - Note: The sizing scan that precedes it — ``Ndb/noteSizeHistogram()`` — has
///   no such exemption. It holds one `ndb_begin_query` transaction open for its
///   whole duration, which on a large database is long enough for another
///   thread's query to trip the 3s watchdog and abort a DEBUG build. Measured at
///   4-9M notes/sec, so it is seconds only on a very large database, and
///   `ndb_stat` already does a strictly larger scan from the storage settings
///   screen. See headway:damus-ios/green-gossip-father.
actor NdbPruneManager {
    /// How often to re-check the database size while the app is in the
    /// foreground. One `stat` per tick, so this is deliberately unhurried.
    static let checkInterval: TimeInterval = 60 * 30

    /// Start pruning at this fraction of the budget rather than at the budget.
    ///
    /// A prune holds a long read transaction open on the source, which stops
    /// LMDB reusing free pages for its duration — so the live database can grow
    /// while the prune runs. Triggering early leaves it somewhere to grow.
    static let triggerFraction: Double = 0.9

    /// Aim the prune at this fraction of the budget, so the result has room to
    /// grow before it trips the trigger again.
    static let targetFraction: Double = 0.75

    /// Free space to insist on beyond the estimated output, since source and
    /// pruned copy coexist on disk for the length of the prune.
    static let freeSpaceMarginBytes: UInt64 = 512 * 1024 * 1024

    /// How long to wait after a failed prune before trying again.
    static let failureBackoff: TimeInterval = 60 * 60 * 6

    /// What a size check concluded.
    enum Decision: Equatable {
        /// Prune, aiming the result at `fileBudget` bytes.
        case prune(fileBudget: UInt64)
        /// The user opted out of a budget entirely.
        case noBudget
        /// Still comfortably inside the budget.
        case underBudget(sizeBytes: UInt64, triggerBytes: UInt64)
        /// A pruned copy is already staged. Pruning again would throw it away
        /// and redo the work for a database the swap is about to replace.
        case alreadyPending
        /// A prune failed recently; leave it alone until this passes.
        case backingOff(until: Date)
        /// Not enough room for the source and the pruned copy at once.
        case notEnoughFreeSpace(neededBytes: UInt64, availableBytes: UInt64)
        /// No database to measure.
        case noDatabase
    }

    private let ndb: Ndb
    /// The authors whose notes survive a prune regardless of age.
    private let keepAuthors: [Pubkey]
    private let dbPath: String?

    private var timerTask: Task<Void, Never>? = nil
    private var isPruning: Bool = false
    /// When the last prune failed, if one has. Read by the backoff, and by the
    /// tests that check a failure is remembered.
    private(set) var lastFailure: Date? = nil

    /// How many prunes have completed, for the developer settings screen.
    private(set) var pruneCount: Int = 0
    /// How many size checks have run, for tests and the developer settings screen.
    private(set) var checkCount: Int = 0

    /// - Parameters:
    ///   - ndb: The live database to prune from.
    ///   - keepAuthors: Authors kept regardless of the cutoff — our own pubkey.
    ///   - dbPath: Override the database directory. Pass `nil` (default) to use
    ///     ``Ndb/db_path``.
    init(ndb: Ndb, keepAuthors: [Pubkey], dbPath: String? = nil) {
        self.ndb = ndb
        self.keepAuthors = keepAuthors
        self.dbPath = dbPath ?? Ndb.db_path
    }

    // MARK: - Periodic checks

    /// Starts checking the database size, now and then periodically.
    ///
    /// Call when the app enters the foreground. The database only grows while
    /// the app is running, so there is nothing to watch in the background.
    func startPeriodicChecks() {
        guard timerTask == nil else {
            Log.debug("Prune timer already running", for: .storage)
            return
        }

        Log.info("Starting periodic nostrdb prune checks", for: .storage)

        timerTask = Task(priority: .utility) { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                do {
                    _ = try await self.pruneIfNeeded()
                } catch {
                    Log.error("Prune failed: %@", for: .storage, String(describing: error))
                }
                try? await Task.sleep(for: .seconds(Self.checkInterval), tolerance: .seconds(60))
            }
        }
    }

    /// Stops the periodic checks.
    ///
    /// Cancels without waiting: a prune in flight can take minutes, and this is
    /// called on the way to the background, where waiting would burn the
    /// suspension budget. An abandoned prune leaves a staged directory with no
    /// marker, which the next attempt clears.
    func stopPeriodicChecks() {
        guard timerTask != nil else { return }
        Log.info("Stopping periodic nostrdb prune checks", for: .storage)
        timerTask?.cancel()
        timerTask = nil
    }

    // MARK: - Deciding

    /// Decides what to do about a database of `databaseSizeBytes`.
    ///
    /// Pure, so the policy can be tested without a database: everything it needs
    /// is passed in.
    static func decide(databaseSizeBytes: UInt64?,
                       budget: NdbSpaceBudget,
                       pendingPrune: NdbPendingPrune?,
                       availableBytes: UInt64?,
                       lastFailure: Date?,
                       now: Date = Date()) -> Decision {
        guard let budgetBytes = budget.bytes else { return .noBudget }
        guard let size = databaseSizeBytes else { return .noDatabase }

        let trigger = UInt64(Double(budgetBytes) * triggerFraction)
        guard size > trigger else {
            return .underBudget(sizeBytes: size, triggerBytes: trigger)
        }

        // Checked before the backoff so a staged copy is reported as what it is
        // rather than as a failure we are waiting out.
        if pendingPrune != nil { return .alreadyPending }

        if let lastFailure {
            let retryAt = lastFailure.addingTimeInterval(failureBackoff)
            if now < retryAt { return .backingOff(until: retryAt) }
        }

        let target = UInt64(Double(budgetBytes) * targetFraction)
        let needed = target + freeSpaceMarginBytes
        // Unknown free space is not a reason to refuse: the prune fails cleanly
        // if the disk fills, and this check is only here to avoid starting a
        // long job that cannot finish.
        if let availableBytes, availableBytes < needed {
            return .notEnoughFreeSpace(neededBytes: needed, availableBytes: availableBytes)
        }

        return .prune(fileBudget: target)
    }

    /// Runs ``decide(databaseSizeBytes:budget:pendingPrune:availableBytes:lastFailure:now:)``
    /// against the real database and filesystem.
    func currentDecision() -> Decision {
        guard let dbPath else { return .noDatabase }
        checkCount += 1
        return Self.decide(databaseSizeBytes: Ndb.database_file_size(path: dbPath),
                           budget: Ndb.get_space_budget(db_path: dbPath),
                           pendingPrune: Ndb.get_pending_prune(),
                           availableBytes: Self.availableBytes(at: dbPath),
                           lastFailure: lastFailure)
    }

    /// Bytes the volume can give us, as iOS reports them for storage worth
    /// keeping. `nil` if the volume will not say.
    static func availableBytes(at path: String) -> UInt64? {
        let values = try? URL(fileURLWithPath: path)
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        guard let capacity = values?.volumeAvailableCapacityForImportantUsage else { return nil }
        return capacity > 0 ? UInt64(capacity) : 0
    }

    // MARK: - Pruning

    /// Prunes if the database has grown past its budget.
    ///
    /// - Returns: Whether a prune ran and staged a database.
    @discardableResult
    func pruneIfNeeded() async throws -> Bool {
        return try await prune(if: currentDecision())
    }

    /// Acts on a decision that has already been made.
    ///
    /// Split from ``pruneIfNeeded()`` so the prune can be driven from a decision
    /// the caller supplies — which is the only way to exercise the whole path
    /// without a database of several gigabytes.
    ///
    /// - Returns: Whether a prune ran and staged a database.
    @discardableResult
    func prune(if decision: Decision) async throws -> Bool {
        guard !isPruning else {
            Log.debug("Prune already in progress", for: .storage)
            return false
        }

        guard case .prune(let fileBudget) = decision else {
            Log.debug("Not pruning: %@", for: .storage, String(describing: decision))
            return false
        }

        isPruning = true
        defer { isPruning = false }

        do {
            let staged = try await stagePrune(fileBudget: fileBudget)
            guard let staged else { return false }
            Ndb.set_pending_prune(NdbPendingPrune(path: staged.path,
                                                  completedAt: Date(),
                                                  promise: staged.promise))
            pruneCount += 1
            Log.info("Staged a pruned database at %@", for: .storage, staged.path)
            return true
        } catch {
            lastFailure = Date()
            throw error
        }
    }

    /// Prunes at the user's explicit request, whether or not the database has
    /// grown past its budget.
    ///
    /// Differs from ``pruneIfNeeded()`` in the two ways a person pressing a
    /// button should: a database comfortably inside its budget is still trimmed
    /// down to the target, and a prune that failed a few hours ago does not hold
    /// this one off. The reasons that are not about timing — no budget to aim
    /// at, a copy already staged, not enough room on the volume — still apply,
    /// and are reported back so the UI can say why nothing happened.
    ///
    /// - Returns: What it did, or why it did nothing.
    func pruneNow() async throws -> ManualPruneOutcome {
        guard let dbPath else { return .noDatabase }
        guard !isPruning else { return .alreadyRunning }

        guard let budgetBytes = Ndb.get_space_budget(db_path: dbPath).bytes else { return .noBudget }
        guard let size = Ndb.database_file_size(path: dbPath), size > 0 else { return .noDatabase }

        // A staged copy is about to replace this database wholesale. Pruning
        // again would bin it and redo minutes of work for a worse result.
        if Ndb.get_pending_prune() != nil { return .alreadyStaged }

        let target = UInt64(Double(budgetBytes) * Self.targetFraction)
        let needed = target + Self.freeSpaceMarginBytes
        if let available = Self.availableBytes(at: dbPath), available < needed {
            return .notEnoughFreeSpace(neededBytes: needed, availableBytes: available)
        }

        let staged = try await prune(if: .prune(fileBudget: target))
        return staged ? .staged : .nothingToPrune
    }

    /// Writes a pruned copy into the staging directory.
    ///
    /// Does not set the pending marker — ``pruneIfNeeded()`` does that once this
    /// returns a result, so a caller driving a prune by hand (a test, the
    /// developer settings screen) does not arm a swap as a side effect.
    ///
    /// - Returns: The staged copy and what its keep-policy promised, or `nil` if
    ///   the notes already fit the budget and there was nothing to drop.
    func stagePrune(fileBudget: UInt64) async throws -> NdbStagedPrune? {
        guard let dbPath else { throw NdbPruneManagerError.missingDatabasePath }
        guard let currentSize = Ndb.database_file_size(path: dbPath), currentSize > 0 else {
            throw NdbPruneManagerError.missingDatabasePath
        }

        let stagedPath = "\(dbPath)/\(Ndb.staged_prune_directory_name)"

        // Anything already here is the wreckage of an abandoned attempt: we only
        // reach this point with no pending marker, so nothing here is wanted.
        try? FileManager.default.removeItem(atPath: stagedPath)
        do {
            // LMDB will not create the destination, and insists on it being empty.
            try FileManager.default.createDirectory(atPath: stagedPath, withIntermediateDirectories: true)
        } catch {
            throw NdbPruneManagerError.createStagingDirectoryFailed(underlyingError: error)
        }

        do {
            let keepAuthors = self.keepAuthors
            let ndb = self.ndb
            let promise = try await Self.offMainPool({ () -> NdbPrunePromise? in
                // One scan, reused for both the total and the cutoff.
                let histogram = try ndb.noteSizeHistogram()
                let noteBudget = Self.noteBudget(forFileBudget: fileBudget,
                                                 databaseSizeBytes: currentSize,
                                                 noteBytes: histogram.totalBytes)

                guard let since = histogram.sinceCutoff(keepingAtMost: noteBudget) else {
                    Log.info("Database is over its file budget but its notes already fit; nothing to prune", for: .storage)
                    return nil
                }

                Log.info("Pruning to %d note bytes, keeping notes since %d", for: .storage, noteBudget, since)
                let filters = try NdbFilterArray.pruneFilters(keeping: keepAuthors, since: since)
                // Read off what this keep-policy promises before pruning, while
                // the source is still the thing to read it from. The swap has
                // nothing else to check the copy against — see
                // ``NdbPrunePromise``.
                let promise = try NdbPrunePromise(source: ndb, keepAuthors: keepAuthors, since: since)
                try ndb.prune(to: stagedPath, filters: filters)
                return promise
            })

            guard let promise else {
                try? FileManager.default.removeItem(atPath: stagedPath)
                return nil
            }

            // A marker must never name a database that is not there: whatever it
            // points at is what gets swapped in.
            guard Ndb.db_file_exists(path: stagedPath),
                  let stagedSize = Ndb.database_file_size(path: stagedPath), stagedSize > 0 else {
                throw NdbPruneManagerError.stagedDatabaseMissingOrEmpty(path: stagedPath)
            }

            Log.info("Pruned %d bytes down to %d bytes", for: .storage, currentSize, stagedSize)
            return NdbStagedPrune(path: stagedPath, promise: promise)
        } catch {
            try? FileManager.default.removeItem(atPath: stagedPath)
            throw error
        }
    }

    /// Turns a `data.mdb` budget into the note-payload budget the histogram
    /// speaks in.
    ///
    /// The histogram counts note values only — no indices, no profile records,
    /// no page overhead — so a file budget handed to it unscaled would keep far
    /// more than it meant to. Scaling by the ratio this database happens to show
    /// is an estimate on purpose: the budget triggers a prune, it is not a cap
    /// that has to be hit exactly.
    static func noteBudget(forFileBudget fileBudget: UInt64,
                           databaseSizeBytes: UInt64,
                           noteBytes: UInt64) -> UInt64 {
        guard databaseSizeBytes > 0 else { return noteBytes }
        // In Double: the integer form overflows for any real database, since the
        // budget alone runs to gigabytes.
        let scaled = Double(fileBudget) / Double(databaseSizeBytes) * Double(noteBytes)
        return UInt64(scaled.rounded())
    }

    /// Runs blocking nostrdb work off the cooperative thread pool.
    ///
    /// A prune takes minutes and a scan takes seconds; both block the thread
    /// they are on, and Swift's cooperative pool has one thread per core to
    /// spare, so running them there would stall unrelated work.
    private static func offMainPool<T>(_ work: @escaping () throws -> T) async throws -> T {
        return try await withCheckedThrowingContinuation({ continuation in
            pruneQueue.async {
                continuation.resume(with: Result(catching: work))
            }
        })
    }

    private static let pruneQueue = DispatchQueue(label: "com.jb55.damus.ndb-prune", qos: .utility)

    // MARK: - Retiring the scheduled-compaction machinery

    /// The `UserDefaults` keys the old scheduled-compaction machinery left on
    /// every install that ever ran it.
    ///
    /// Nothing reads these any more — the code that did was deleted along with
    /// `Ndb+Compaction.swift` — so they are dead weight in the app's defaults,
    /// and `ndb_compact_on_next_launch` in particular is a flag no launch will
    /// ever act on again.
    static let legacyCompactionDefaultsKeys = [
        "ndb_auto_compact_schedule",
        "ndb_last_compact_date",
        "ndb_compact_on_next_launch",
        "ndb_compact_on_next_launch_source",
        "ndb_large_db_compaction_notification_pending",
    ]

    /// Removes the defaults the scheduled-compaction machinery left behind.
    ///
    /// Safe to call on every launch: `removeObject` on a key that is not there
    /// does nothing, so this needs no "have I run yet" flag of its own — which
    /// would only be one more stale key to retire later.
    ///
    /// An install updating with `ndb_compact_on_next_launch` still set is not
    /// stranded by this. That flag only ever meant "the database wants
    /// shrinking", and the size-budgeted prune answers the same question
    /// without being asked: ``startPeriodicChecks()`` runs a check as soon as
    /// the app reaches the foreground, and stages a pruned copy if the database
    /// is over its budget. So the user's intent is honoured on the first
    /// foreground rather than the next launch, and by something that actually
    /// drops notes rather than only reclaiming free pages.
    static func removeLegacyCompactionDefaults() {
        let defaults = UserDefaults.standard
        let hadPendingCompaction = defaults.bool(forKey: "ndb_compact_on_next_launch")

        for key in legacyCompactionDefaultsKeys {
            defaults.removeObject(forKey: key)
        }

        if hadPendingCompaction {
            Log.info("Discarded a pending scheduled compaction; the space budget governs the database now", for: .storage)
        }
    }
}

// MARK: - Reporting the launch-time swap

extension NdbPruneManager {
    /// Reports a launch-time swap that did not go through.
    ///
    /// ``Ndb/swap_staged_prune_before_first_open(db_path:)`` lives in
    /// `Ndb+PruneSwap.swift`, which is compiled into the extensions too, where
    /// Sentry does not exist — so all it can do is leave its outcome in
    /// ``Ndb/staged_prune_swap_outcome`` for someone in the app target to pick
    /// up. This is that someone, and it restores the error reporting the old
    /// `CompactionView` used to do.
    ///
    /// Only refusals and failures are worth a report. A refusal means the budget
    /// quietly stopped being enforced for this user, or that the validation is
    /// misfiring on databases we would in fact have been happy with; either way
    /// it is invisible from the outside and needs telling.
    @MainActor
    static func reportStagedPruneSwapOutcome() {
        guard !hasReportedSwapOutcome else { return }
        hasReportedSwapOutcome = true

        guard let outcome = Ndb.staged_prune_swap_outcome else { return }

        switch outcome {
        case .nothingStaged, .notForThisDatabase:
            break
        case .swapped(let bytes):
            Log.info("Swapped in a staged pruned database of %d bytes", for: .storage, bytes)
        case .refused(let rejection):
            Log.error("Refused a staged pruned database: %@", for: .storage, String(describing: rejection))
            DamusSentry.captureSentryMessage("Refused a staged pruned database") { scope in
                scope.setContext(value: ["reason": String(describing: rejection)], key: "prune_swap")
            }
        case .failed(let description):
            Log.error("Staged prune swap failed: %@", for: .storage, description)
            DamusSentry.captureSentryMessage("Staged prune swap failed") { scope in
                scope.setContext(value: ["error": description], key: "prune_swap")
            }
        }
    }

    /// The swap happens once per process, so its outcome is worth reporting
    /// once — not again for every `DamusState` a logout and login builds.
    @MainActor
    private static var hasReportedSwapOutcome = false
}

/// What a user-initiated prune did, or why it did nothing.
enum ManualPruneOutcome: Equatable {
    /// A pruned copy is staged, and swaps in at the next launch.
    case staged

    /// The database is over its file budget, but its notes already fit inside
    /// the note budget — the rest is index and page overhead a prune cannot
    /// reach. Nothing was staged.
    case nothingToPrune

    /// A pruned copy was already staged and waiting. Restarting applies it.
    case alreadyStaged

    /// A prune is already running, so this one was not started.
    case alreadyRunning

    /// The user chose not to cap the database, so there is no size to prune
    /// towards.
    case noBudget

    /// The volume cannot hold the source and the pruned copy at once, and they
    /// coexist for the length of the prune.
    case notEnoughFreeSpace(neededBytes: UInt64, availableBytes: UInt64)

    /// There is no database to prune.
    case noDatabase
}

/// A pruned copy sitting in the staging directory, ready for a marker to arm a
/// swap with.
struct NdbStagedPrune: Equatable {
    /// The staging directory, holding a complete, closed, standalone database.
    let path: String

    /// What the keep-policy that produced it promised to carry over.
    let promise: NdbPrunePromise
}

/// Errors from staging a prune.
enum NdbPruneManagerError: Error, LocalizedError {
    case missingDatabasePath
    case createStagingDirectoryFailed(underlyingError: Error)
    case stagedDatabaseMissingOrEmpty(path: String)

    var errorDescription: String? {
        switch self {
        case .missingDatabasePath:
            return "Could not determine the database path."
        case .createStagingDirectoryFailed(let underlyingError):
            return "Failed to create the prune staging directory: \(underlyingError.localizedDescription)"
        case .stagedDatabaseMissingOrEmpty(let path):
            return "The pruned database at \(path) is missing or empty."
        }
    }
}
