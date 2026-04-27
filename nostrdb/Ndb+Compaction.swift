//
//  Ndb+Compaction.swift
//  damus
//

import Foundation

/// A progress update emitted while database compaction advances through its major stages.
struct NdbCompactionProgress: Equatable {
    /// A stable identifier for the current compaction stage.
    enum Step: Int, CaseIterable, Equatable {
        case preparing
        case creatingTempDirectory
        case openingDatabase
        case creatingSnapshot
        case validatingSnapshot
        case replacingDatabase
        case cleaningUp
        case completed

        /// The user-facing title for the current stage.
        var title: String {
            switch self {
            case .preparing:
                return NSLocalizedString("Preparing database compaction", comment: "Compaction progress stage title")
            case .creatingTempDirectory:
                return NSLocalizedString("Creating temporary workspace", comment: "Compaction progress stage title")
            case .openingDatabase:
                return NSLocalizedString("Opening database", comment: "Compaction progress stage title")
            case .creatingSnapshot:
                return NSLocalizedString("Creating compacted snapshot", comment: "Compaction progress stage title")
            case .validatingSnapshot:
                return NSLocalizedString("Validating compacted database", comment: "Compaction progress stage title")
            case .replacingDatabase:
                return NSLocalizedString("Replacing database files", comment: "Compaction progress stage title")
            case .cleaningUp:
                return NSLocalizedString("Cleaning up temporary files", comment: "Compaction progress stage title")
            case .completed:
                return NSLocalizedString("Finishing up", comment: "Compaction progress stage title")
            }
        }

        /// A short user-facing description for the current stage.
        var detail: String {
            switch self {
            case .preparing:
                return NSLocalizedString("Checking the database and getting everything ready.", comment: "Compaction progress stage detail")
            case .creatingTempDirectory:
                return NSLocalizedString("Setting up a temporary location for the compacted copy.", comment: "Compaction progress stage detail")
            case .openingDatabase:
                return NSLocalizedString("Opening the existing database safely in the background.", comment: "Compaction progress stage detail")
            case .creatingSnapshot:
                return NSLocalizedString("Copying data into a smaller optimized database file. This is usually the longest step.", comment: "Compaction progress stage detail")
            case .validatingSnapshot:
                return NSLocalizedString("Making sure the compacted database looks valid before replacing the original.", comment: "Compaction progress stage detail")
            case .replacingDatabase:
                return NSLocalizedString("Swapping in the optimized database files.", comment: "Compaction progress stage detail")
            case .cleaningUp:
                return NSLocalizedString("Removing temporary files and recording completion.", comment: "Compaction progress stage detail")
            case .completed:
                return NSLocalizedString("Database optimization is complete.", comment: "Compaction progress stage detail")
            }
        }

        /// The zero-based index of the step in the overall compaction flow.
        var index: Int {
            return Self.allCases.firstIndex(of: self) ?? 0
        }

        /// The total number of steps in the overall compaction flow.
        static var totalCount: Int {
            return Self.allCases.count
        }
    }

    /// The current compaction stage.
    let step: Step

    /// The fraction completed for the overall compaction flow.
    var fractionCompleted: Double {
        guard Step.totalCount > 1 else { return 1.0 }
        return Double(step.index) / Double(Step.totalCount - 1)
    }
}

/// Defines how often the database should be automatically compacted.
enum AutoCompactSchedule: String, CaseIterable, Equatable {
    case daily
    case weekly
    case monthly
    case never

    /// Human-readable label shown in the settings UI.
    func text_description() -> String {
        switch self {
        case .daily:
            return NSLocalizedString("Once a day", comment: "Auto-compact schedule option: compact once a day")
        case .weekly:
            return NSLocalizedString("Once a week", comment: "Auto-compact schedule option: compact once a week")
        case .monthly:
            return NSLocalizedString("Once a month", comment: "Auto-compact schedule option: compact once a month")
        case .never:
            return NSLocalizedString("Never", comment: "Auto-compact schedule option: never auto-compact")
        }
    }

    /// The time interval (in seconds) between automatic compactions, or `nil` for `.never`.
    var interval: TimeInterval? {
        switch self {
        case .daily:   return 60 * 60 * 24
        case .weekly:  return 60 * 60 * 24 * 7
        case .monthly: return 60 * 60 * 24 * 30
        case .never:   return nil
        }
    }
}

extension Ndb {
    /// Errors that can occur while compacting the database.
    enum CompactionError: LocalizedError {
        case missingDatabasePath
        case createTempDirectoryFailed(underlyingError: Error)
        case openDatabaseFailed(path: String)
        case snapshotFailed(underlyingError: Error)
        case compactedFileMissingOrEmpty(path: String)
        case replaceDatabaseFailed(underlyingError: Error)
        case postReplaceSizeMismatch(expected: Int, actual: Int)
        
        /// A user-presentable description of the compaction failure.
        var errorDescription: String? {
            switch self {
            case .missingDatabasePath:
                return "Could not determine the database path."
            case .createTempDirectoryFailed(let underlyingError):
                return "Failed to create the temporary compaction directory: \(underlyingError.localizedDescription)"
            case .openDatabaseFailed(let path):
                return "Failed to open the database for compaction at path: \(path)"
            case .snapshotFailed(let underlyingError):
                return "Failed to create a compacted database snapshot: \(underlyingError.localizedDescription)"
            case .compactedFileMissingOrEmpty(let path):
                return "The compacted database file is missing or empty at path: \(path)"
            case .replaceDatabaseFailed(let underlyingError):
                return "Failed to replace the original database with the compacted copy: \(underlyingError.localizedDescription)"
            case .postReplaceSizeMismatch(let expected, let actual):
                return "The compacted database size verification failed. Expected \(expected) bytes, got \(actual) bytes."
            }
        }
    }
    
    /// Makes a compacted copy of the database in a separate directory.
    ///
    /// This uses `mdb_env_copy2` with `MDB_CP_COMPACT` (flag = 0x01), which omits free pages
    /// and sequentially renumbers all pages in the output, reducing database file size.
    /// - Parameter path: The directory path where the compacted database will be written.
    ///                   The directory must already exist and be empty.
    func compact(to path: String) throws {
        enum CompactError: Error {
            case mdbOperationError(errno: Int32)
        }

        try withNdb({
            try path.withCString({ pathCString in
                let rc = ndb_snapshot(self.ndb.ndb, pathCString, Self.MDB_CP_COMPACT)
                guard rc == 0 else {
                    throw CompactError.mdbOperationError(errno: rc)
                }
            })
        })
    }

    /// LMDB compact-copy flag.  Passed to `ndb_snapshot` / `mdb_env_copy2` to produce a
    /// compacted (free-page-omitting) database copy.  Mirrors `MDB_CP_COMPACT = 0x01` from lmdb.h.
    private static let MDB_CP_COMPACT: UInt32 = 1

    /// Name of the temporary subdirectory created during an in-place compaction.
    private static let compactTempDirName = "ndb_compact_temp"

    /// The `UserDefaults` key used to signal that the database should be compacted on the next app launch.
    static let compact_on_next_launch_key = "ndb_compact_on_next_launch"

    /// The `UserDefaults` key used to persist the auto-compact schedule (stored as raw string).
    static let auto_compact_schedule_key = "ndb_auto_compact_schedule"

    /// The `UserDefaults` key used to record when the last successful compaction occurred.
    static let last_compact_date_key = "ndb_last_compact_date"

    /// Requests that the database be compacted the next time the app launches.
    ///
    /// Call this to schedule a one-time compaction. The flag is cleared automatically after
    /// a successful compaction in `compact_if_needed()`.
    static func set_compact_on_next_launch() {
        UserDefaults.standard.set(true, forKey: compact_on_next_launch_key)
    }

    /// Reads the persisted auto-compact schedule from `UserDefaults`.
    ///
    /// Defaults to `.weekly` if no value has been saved yet.
    static func get_auto_compact_schedule() -> AutoCompactSchedule {
        guard let raw = UserDefaults.standard.string(forKey: auto_compact_schedule_key),
              let schedule = AutoCompactSchedule(rawValue: raw) else {
            return .weekly
        }
        return schedule
    }

    /// Persists the auto-compact schedule to `UserDefaults`.
    static func set_auto_compact_schedule(_ schedule: AutoCompactSchedule) {
        UserDefaults.standard.set(schedule.rawValue, forKey: auto_compact_schedule_key)
    }

    /// Returns the date of the last successful compaction, or `nil` if none has occurred.
    static func get_last_compact_date() -> Date? {
        return UserDefaults.standard.object(forKey: last_compact_date_key) as? Date
    }

    /// Sets the compact-on-next-launch flag if the scheduled interval has elapsed since the
    /// last successful compaction.
    ///
    /// Call this once on app startup **before** `compact_if_needed()`.
    static func schedule_auto_compact_if_needed() {
        let schedule = get_auto_compact_schedule()
        guard let interval = schedule.interval else { return }

        let now = Date()
        let lastDate = get_last_compact_date() ?? .distantPast
        guard now.timeIntervalSince(lastDate) >= interval else { return }

        Log.info("Auto-compact: interval elapsed — scheduling compaction on next launch", for: .storage)
        set_compact_on_next_launch()
    }

    /// Compacts the NostrDB database files if the compact-on-next-launch flag is set.
    ///
    /// This is intended to be called once during app startup **before** `Ndb` is opened for
    /// normal use.  The algorithm is:
    ///   1. Open a temporary `Ndb` instance at the same path to access the LMDB environment.
    ///   2. Write a compacted copy of the database to a sibling temp directory.
    ///   3. Close the temporary `Ndb` instance.
    ///   4. Atomically replace the original `data.mdb` with the compacted copy.
    ///   5. Remove the temp directory.
    ///   6. Clear the flag so compaction does not run again on the following launch.
    ///
    /// - Parameters:
    ///   - db_path: Override the database directory path. Pass `nil` (default) to use
    ///     `Ndb.db_path`. Mainly useful for testing.
    ///   - progress: An optional callback invoked as the compaction advances through major stages.
    /// - Throws: `CompactionError` when compaction was requested but could not be completed.
    static func compact_if_needed(
        db_path: String? = nil,
        progress: ((NdbCompactionProgress) -> Void)? = nil
    ) throws {
        guard UserDefaults.standard.bool(forKey: compact_on_next_launch_key) else { return }

        progress?(.init(step: .preparing))

        guard let path = db_path ?? Self.db_path else {
            Log.error("compact_if_needed: could not determine db path", for: .storage)
            throw CompactionError.missingDatabasePath
        }

        guard db_file_exists(path: path) else {
            // No database file present yet; nothing to compact — just clear the flag.
            UserDefaults.standard.set(false, forKey: compact_on_next_launch_key)
            progress?(.init(step: .completed))
            return
        }

        Log.info("Compacting NostrDB on startup…", for: .storage)

        let tempPath = "\(path)/\(compactTempDirName)"

        // Clean up any leftover temp directory from a previously failed attempt.
        try? FileManager.default.removeItem(atPath: tempPath)

        progress?(.init(step: .creatingTempDirectory))

        do {
            try FileManager.default.createDirectory(atPath: tempPath, withIntermediateDirectories: true)
        } catch {
            Log.error("compact_if_needed: failed to create temp dir: %@", for: .storage, String(describing: error))
            throw CompactionError.createTempDirectoryFailed(underlyingError: error)
        }

        progress?(.init(step: .openingDatabase))

        // Open a temporary Ndb instance just to drive the compaction.
        guard let tempNdb = Ndb(path: path) else {
            Log.error("compact_if_needed: failed to open ndb for compaction", for: .storage)
            try? FileManager.default.removeItem(atPath: tempPath)
            throw CompactionError.openDatabaseFailed(path: path)
        }
        // Ensure the temporary Ndb is closed regardless of how this function exits.
        defer { tempNdb.close() }

        progress?(.init(step: .creatingSnapshot))

        do {
            try tempNdb.compact(to: tempPath)
        } catch {
            Log.error("compact_if_needed: compaction failed: %@", for: .storage, String(describing: error))
            try? FileManager.default.removeItem(atPath: tempPath)
            throw CompactionError.snapshotFailed(underlyingError: error)
        }

        tempNdb.close()

        progress?(.init(step: .validatingSnapshot))

        // Atomically replace the original data.mdb with the compacted copy.
        let originalDataMdb = URL(fileURLWithPath: "\(path)/\(main_db_file_name)")
        let compactedDataMdb = URL(fileURLWithPath: "\(tempPath)/\(main_db_file_name)")

        // Validate the compacted file before replacing the original.
        let originalSize = (try? FileManager.default.attributesOfItem(atPath: originalDataMdb.path)[.size] as? Int) ?? 0
        let compactedSize = (try? FileManager.default.attributesOfItem(atPath: compactedDataMdb.path)[.size] as? Int) ?? 0
        Log.info("compact_if_needed: original=%d bytes, compacted=%d bytes", for: .storage, originalSize, compactedSize)

        guard compactedSize > 0 else {
            Log.error("compact_if_needed: compacted file is missing or empty — aborting", for: .storage)
            try? FileManager.default.removeItem(atPath: tempPath)
            throw CompactionError.compactedFileMissingOrEmpty(path: compactedDataMdb.path)
        }

        progress?(.init(step: .replacingDatabase))

        // Delete the stale lock.mdb BEFORE replacing data.mdb.
        // The temp Ndb wrote reader-table / txn state into lock.mdb that references
        // pages in the old data.mdb. After data.mdb is replaced with the smaller
        // compacted copy, those page references become invalid and cause SIGBUS.
        // LMDB will recreate a fresh lock file on the next open.
        let lockPath = "\(path)/lock.mdb"
        try? FileManager.default.removeItem(atPath: lockPath)

        do {
            _ = try FileManager.default.replaceItemAt(
                originalDataMdb,
                withItemAt: compactedDataMdb,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        } catch {
            Log.error("compact_if_needed: failed to replace db file: %@", for: .storage, String(describing: error))
            try? FileManager.default.removeItem(atPath: tempPath)
            throw CompactionError.replaceDatabaseFailed(underlyingError: error)
        }

        // Post-replace sanity check: verify the destination file exists with the expected size.
        let finalSize = (try? FileManager.default.attributesOfItem(atPath: originalDataMdb.path)[.size] as? Int) ?? 0
        if finalSize != compactedSize {
            Log.error("compact_if_needed: post-replace size mismatch — expected %d, got %d", for: .storage, compactedSize, finalSize)
            try? FileManager.default.removeItem(atPath: tempPath)
            throw CompactionError.postReplaceSizeMismatch(expected: compactedSize, actual: finalSize)
        }

        progress?(.init(step: .cleaningUp))

        Log.info("NostrDB compacted successfully", for: .storage)

        // Clean up the temp directory (any remaining files such as lock.mdb).
        try? FileManager.default.removeItem(atPath: tempPath)

        // Record the date of this successful compaction for the auto-compact scheduler.
        UserDefaults.standard.set(Date(), forKey: last_compact_date_key)

        // Clear the flag so we don't compact again on the next launch.
        UserDefaults.standard.set(false, forKey: compact_on_next_launch_key)

        progress?(.init(step: .completed))
    }
}
