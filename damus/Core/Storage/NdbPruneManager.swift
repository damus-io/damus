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

    /// The staging directory, a sibling of `data.mdb` inside the database
    /// directory.
    ///
    /// Deliberately not the system temporary directory: a staged prune has to
    /// survive until the next launch, and iOS is free to empty `tmp` in between.
    static let stagedDirectoryName = "ndb_prune_staged"

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
            Ndb.set_pending_prune(NdbPendingPrune(path: staged, completedAt: Date()))
            pruneCount += 1
            Log.info("Staged a pruned database at %@", for: .storage, staged)
            return true
        } catch {
            lastFailure = Date()
            throw error
        }
    }

    /// Writes a pruned copy into the staging directory.
    ///
    /// Does not set the pending marker — ``pruneIfNeeded()`` does that once this
    /// returns a path, so a caller driving a prune by hand (a test, the developer
    /// settings screen) does not arm a swap as a side effect.
    ///
    /// - Returns: The staging path, or `nil` if the notes already fit the budget
    ///   and there was nothing to drop.
    func stagePrune(fileBudget: UInt64) async throws -> String? {
        guard let dbPath else { throw NdbPruneManagerError.missingDatabasePath }
        guard let currentSize = Ndb.database_file_size(path: dbPath), currentSize > 0 else {
            throw NdbPruneManagerError.missingDatabasePath
        }

        let stagedPath = "\(dbPath)/\(Self.stagedDirectoryName)"

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
            let didPrune = try await Self.offMainPool({
                // One scan, reused for both the total and the cutoff.
                let histogram = try ndb.noteSizeHistogram()
                let noteBudget = Self.noteBudget(forFileBudget: fileBudget,
                                                 databaseSizeBytes: currentSize,
                                                 noteBytes: histogram.totalBytes)

                guard let since = histogram.sinceCutoff(keepingAtMost: noteBudget) else {
                    Log.info("Database is over its file budget but its notes already fit; nothing to prune", for: .storage)
                    return false
                }

                Log.info("Pruning to %d note bytes, keeping notes since %d", for: .storage, noteBudget, since)
                let filters = try NdbFilterArray.pruneFilters(keeping: keepAuthors, since: since)
                try ndb.prune(to: stagedPath, filters: filters)
                return true
            })

            guard didPrune else {
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
            return stagedPath
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
