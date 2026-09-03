//
//  Ndb+PruneSwap.swift
//  damus
//
//  Moves a pruned database staged by an earlier session into place, before
//  nostrdb maps anything. This is why the launch-time progress screen could go
//  away: the expensive part already happened in the background while the app
//  was live, and what is left at launch is a rename plus a few index seeks.
//

import Foundation

/// What a launch-time swap attempt concluded.
enum NdbPruneSwapOutcome: Equatable {
    /// No prune is staged. The overwhelmingly common case, and the one that has
    /// to cost nothing: one `UserDefaults` read.
    case nothingStaged

    /// The marker names a staging directory that does not belong to the database
    /// being opened — a test's temp directory, the read-only snapshot in the
    /// shared container. Left completely alone, marker included.
    case notForThisDatabase(stagedPath: String)

    /// The staged database was moved into place, and was `bytes` big.
    case swapped(bytes: UInt64)

    /// The staged database was not one we would vouch for, and has been deleted
    /// along with its marker.
    case refused(NdbStagedPruneRejection)

    /// The move itself failed. The live database is untouched — `replaceItemAt`
    /// either swaps or does nothing — but its `lock.mdb` is gone, which LMDB
    /// recreates on the open that follows.
    case failed(description: String)
}

/// Why a staged pruned database was refused.
///
/// Every one of these bins the staged copy and clears the marker. Nothing is
/// lost by doing so: the prune runs in the background, so the next size check
/// simply stages a fresh one with an up-to-date cutoff, and that is always
/// better than swapping in a copy we cannot vouch for.
enum NdbStagedPruneRejection: Equatable {
    /// The marker outlived the database it named. iOS can delete files
    /// underneath us, and a swap interrupted after the move but before the
    /// marker was cleared lands here too, which is what makes that crash
    /// window self-healing.
    case missingOrEmpty(path: String)

    /// The copy finished too long ago — see ``Ndb/staged_prune_expiry``.
    case tooStale(age: TimeInterval, limit: TimeInterval)

    /// The copy is a tiny fraction of the database it would replace — see
    /// ``Ndb/minimum_staged_prune_fraction``.
    case tooSmall(bytes: UInt64, floor: UInt64)

    /// nostrdb would not open the copy at all.
    case cannotOpen(path: String)

    /// The copy opened but could not answer a query.
    case validationFailed(description: String)

    /// The source had profiles and the copy has none, though the keep-policy
    /// keeps every one of them.
    case noProfiles

    /// The copy holds none of the text notes of an author the keep-policy keeps
    /// in full — their own posts, dropped.
    case missingAuthor(Pubkey)

    /// The copy holds nothing at or after the cutoff, though the cutoff is by
    /// construction the start of a day the source had notes in. A bad cutoff or
    /// a filter that did not take looks exactly like this.
    case nothingAfterCutoff(since: UInt32)
}

/// The once-per-process latch for the swap, and where its outcome is left for
/// whoever wants to report it.
///
/// A class holding an `NSLock` rather than a `Mutex`, which needs iOS 18 — above
/// our floor. See `Ndb.FallbackUseLock` for the same trade-off.
private final class NdbStagedPruneSwapState: @unchecked Sendable {
    private let lock = NSLock()
    private var attempted = false
    private var outcome: NdbPruneSwapOutcome? = nil

    /// Claims the one attempt this process gets. `true` for the first caller only.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !attempted else { return false }
        attempted = true
        return true
    }

    func record(_ outcome: NdbPruneSwapOutcome) {
        lock.lock()
        defer { lock.unlock() }
        self.outcome = outcome
    }

    func reset() {
        lock.lock()
        defer { lock.unlock() }
        attempted = false
        outcome = nil
    }

    var recorded: NdbPruneSwapOutcome? {
        lock.lock()
        defer { lock.unlock() }
        return outcome
    }
}

extension Ndb {
    /// How stale a staged prune may be before the swap throws it away instead.
    ///
    /// The swap discards everything ingested since the prune finished. Notes
    /// only arrive while the app runs, but iOS keeps an app warm for days, so a
    /// session that stages a prune can go on ingesting long past it without ever
    /// cold-launching. Three days bounds that loss to roughly a long weekend of
    /// reading.
    ///
    /// Erring on the eager side is deliberate: expiring costs a background
    /// prune that has to run again, while swapping in a stale copy costs the
    /// user notes. Those are not comparable.
    static let staged_prune_expiry: TimeInterval = 60 * 60 * 24 * 3

    /// The smallest a staged pruned database may be, as a fraction of the live
    /// database it would replace.
    ///
    /// A prune aims at 75% of the budget and only ever runs once the database is
    /// past 90% of it, so a healthy staged copy is within a small factor of what
    /// it replaces. A copy orders of magnitude smaller is the exact shape of the
    /// failure this validation exists for. A sixty-fourth leaves generous room
    /// for a legitimately deep prune while still catching that by two orders of
    /// magnitude.
    ///
    /// A fraction rather than a byte floor on purpose: any absolute number is
    /// either too small to catch anything on a multi-gigabyte database or too
    /// large to let a small one through. This is the cheap pre-filter either
    /// way — ``validate_staged_prune(at:promise:)`` is the real gate.
    static let minimum_staged_prune_fraction: Double = 1.0 / 64.0

    private static let staged_prune_swap_state = NdbStagedPruneSwapState()

    /// What this process's swap attempt concluded, or `nil` if it has not run.
    ///
    /// The swap is silent by design — it is a rename, there is nothing to show a
    /// progress bar for — but a refusal is worth knowing about: it means a
    /// budget quietly stopped being enforced, or that the validation itself is
    /// misfiring. This is where a diagnostics surface can read it back.
    static var staged_prune_swap_outcome: NdbPruneSwapOutcome? {
        return staged_prune_swap_state.recorded
    }

    /// Swaps a staged pruned database into place, at most once per process,
    /// before the database at `db_path` is opened.
    ///
    /// Called from ``Ndb/open(path:owns_db_file:callbackHandler:)`` rather than
    /// from app startup on purpose. "Before nostrdb opens" is the whole safety
    /// property here, and hanging the swap off the open itself is the only way
    /// to make it structurally true whichever code path opens the database
    /// first.
    ///
    /// Once per process, because the swap deletes `lock.mdb` and replaces
    /// `data.mdb` underneath anything holding them. That is safe on the first
    /// open, when nothing in the process has the database mapped, and is not
    /// safe on a ``reopen()`` with another `Ndb` instance still live on the same
    /// files.
    static func swap_staged_prune_before_first_open(db_path: String) {
        guard staged_prune_swap_state.claim() else { return }

        let outcome = swap_staged_prune(db_path: db_path)
        staged_prune_swap_state.record(outcome)
    }

    /// Un-claims this process's swap attempt.
    ///
    /// Exists so a test can exercise the open-time wiring, which is the part
    /// that makes "before nostrdb maps anything" true and the part a unit test
    /// of ``swap_staged_prune(db_path:now:)`` alone cannot reach. Calling it in
    /// a live app would let a second swap run with the database already mapped,
    /// which is exactly what the latch is there to prevent.
    static func reset_staged_prune_swap_state_for_testing() {
        staged_prune_swap_state.reset()
    }

    /// Swaps the staged pruned database the marker names into place at `db_path`.
    ///
    /// Nothing here touches the live database until the staged copy has passed
    /// validation, and a copy that fails it is deleted along with its marker.
    ///
    /// - Parameters:
    ///   - db_path: The database directory about to be opened.
    ///   - now: The clock, for testing staleness.
    @discardableResult
    static func swap_staged_prune(db_path: String, now: Date = Date()) -> NdbPruneSwapOutcome {
        guard let pending = get_pending_prune() else { return .nothingStaged }

        // The marker is process-wide but a process opens several databases: the
        // read-only snapshot for the extensions, a test's temp directory. Only
        // the staging directory belonging to *this* database may be swapped, and
        // only over the database it was pruned from.
        let stagedPath = "\(db_path)/\(staged_prune_directory_name)"
        guard pending.path == stagedPath else {
            return .notForThisDatabase(stagedPath: pending.path)
        }

        let liveSize = database_file_size(path: db_path)

        if let rejection = evaluate_staged_prune(pending, liveSizeBytes: liveSize, now: now) {
            Log.error("Refusing the staged pruned database at %@: %@", for: .storage,
                      pending.path, String(describing: rejection))
            discard_staged_prune(at: pending.path)
            return .refused(rejection)
        }

        let stagedSize = database_file_size(path: stagedPath) ?? 0
        let live = URL(fileURLWithPath: "\(db_path)/\(main_db_file_name)")
        let staged = URL(fileURLWithPath: "\(stagedPath)/\(main_db_file_name)")

        // Delete the stale lock.mdb BEFORE replacing data.mdb.
        // The session that staged this prune wrote reader-table / txn state into
        // lock.mdb that references pages in the old data.mdb. After data.mdb is
        // replaced with the smaller pruned copy, those page references become
        // invalid and cause SIGBUS.
        // LMDB will recreate a fresh lock file on the next open.
        try? FileManager.default.removeItem(atPath: "\(db_path)/lock.mdb")

        do {
            if db_file_exists(path: db_path) {
                _ = try FileManager.default.replaceItemAt(
                    live,
                    withItemAt: staged,
                    backupItemName: nil,
                    options: [.usingNewMetadataOnly]
                )
            } else {
                // The live database went missing under us — iOS purging the
                // container, say. The pruned copy is then the only one left, so
                // moving it in is a recovery rather than a swap.
                try FileManager.default.moveItem(at: staged, to: live)
            }
        } catch {
            Log.error("Failed to swap in the staged pruned database: %@", for: .storage, String(describing: error))
            return .failed(description: String(describing: error))
        }

        // Only now the marker goes, and in this order: clearing it first would
        // lose the pruned database outright if the process died in between,
        // whereas dying here leaves a marker whose `data.mdb` has already moved,
        // which the next launch refuses as missing and cleans up.
        discard_staged_prune(at: stagedPath)

        Log.info("Swapped in a pruned database of %d bytes", for: .storage, stagedSize)
        return .swapped(bytes: stagedSize)
    }

    /// Checks a staged pruned database against what its prune promised.
    ///
    /// Ordered cheapest first: a file stat, a clock comparison and a size ratio
    /// before anything opens nostrdb.
    ///
    /// - Parameters:
    ///   - pending: The marker, carrying the keep-policy's promises.
    ///   - liveSizeBytes: The size of the database this copy would replace, or
    ///     `nil` if it cannot be measured — in which case there is no ratio to
    ///     check and the content checks stand alone.
    ///   - now: The clock, for testing staleness.
    /// - Returns: The reason to refuse the copy, or `nil` if it may be swapped in.
    static func evaluate_staged_prune(_ pending: NdbPendingPrune,
                                      liveSizeBytes: UInt64?,
                                      now: Date = Date()) -> NdbStagedPruneRejection? {
        guard db_file_exists(path: pending.path),
              let stagedSize = database_file_size(path: pending.path), stagedSize > 0 else {
            return .missingOrEmpty(path: pending.path)
        }

        // Only real staleness counts. A negative age means the clock moved
        // backwards, which says nothing about the copy.
        let age = now.timeIntervalSince(pending.completedAt)
        if age > staged_prune_expiry {
            return .tooStale(age: age, limit: staged_prune_expiry)
        }

        if let liveSizeBytes {
            let floor = UInt64(Double(liveSizeBytes) * minimum_staged_prune_fraction)
            guard stagedSize >= floor else {
                return .tooSmall(bytes: stagedSize, floor: floor)
            }
        }

        return validate_staged_prune(at: pending.path, promise: pending.promise)
    }

    /// Opens the staged database and checks it holds what the keep-policy
    /// promised.
    ///
    /// This is the check that matters. The lossless compaction this replaced
    /// could get away with `size > 0`, because a page copy either works or does
    /// not. A prune decides what to drop, so a wrong decision produces a valid
    /// database with the wrong contents, and a size check waves it straight
    /// through.
    ///
    /// Three indexed existence checks against a database nothing else has open,
    /// so the cost is an `ndb_init` and a handful of seeks.
    ///
    /// - Returns: The reason to refuse the copy, or `nil` if it holds up.
    static func validate_staged_prune(at path: String, promise: NdbPrunePromise) -> NdbStagedPruneRejection? {
        guard let staged = Ndb(path: path, owns_db_file: false) else {
            return .cannotOpen(path: path)
        }
        defer { staged.close() }

        do {
            if promise.hasProfiles,
               try !staged.containsNote(matching: NostrFilter(kinds: [.metadata])) {
                return .noProfiles
            }

            for author in promise.authorsWithPosts {
                if try !staged.containsNote(matching: NostrFilter(kinds: [.text], authors: [author])) {
                    return .missingAuthor(author)
                }
            }

            guard try staged.containsNote(matching: NostrFilter(since: promise.since)) else {
                return .nothingAfterCutoff(since: promise.since)
            }
        } catch {
            // A database that cannot answer a query is not one to swap in.
            return .validationFailed(description: String(describing: error))
        }

        return nil
    }

    /// Deletes a staging directory and forgets the marker naming it.
    ///
    /// Used both after a successful swap, where only `lock.mdb` is left to
    /// clear, and to bin a copy we refused.
    private static func discard_staged_prune(at path: String) {
        try? FileManager.default.removeItem(atPath: path)
        clear_pending_prune()
    }
}
