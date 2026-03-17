//
//  Ndb+Compaction.swift
//  damus
//

import Foundation

extension Ndb {
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

    /// Requests that the database be compacted the next time the app launches.
    ///
    /// Call this to schedule a one-time compaction. The flag is cleared automatically after
    /// a successful compaction in `compact_if_needed()`.
    static func set_compact_on_next_launch() {
        UserDefaults.standard.set(true, forKey: compact_on_next_launch_key)
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
    /// - Parameter db_path: Override the database directory path.  Pass `nil` (default) to use
    ///   `Ndb.db_path`.  Mainly useful for testing.
    static func compact_if_needed(db_path: String? = nil) {
        guard UserDefaults.standard.bool(forKey: compact_on_next_launch_key) else { return }

        guard let path = db_path ?? Self.db_path else {
            Log.error("compact_if_needed: could not determine db path", for: .storage)
            return
        }

        guard db_file_exists(path: path) else {
            // No database file present yet; nothing to compact — just clear the flag.
            UserDefaults.standard.set(false, forKey: compact_on_next_launch_key)
            return
        }

        Log.info("Compacting NostrDB on startup…", for: .storage)

        let tempPath = "\(path)/\(compactTempDirName)"

        // Clean up any leftover temp directory from a previously failed attempt.
        try? FileManager.default.removeItem(atPath: tempPath)

        do {
            try FileManager.default.createDirectory(atPath: tempPath, withIntermediateDirectories: true)
        } catch {
            Log.error("compact_if_needed: failed to create temp dir: %@", for: .storage, String(describing: error))
            return
        }

        // Open a temporary Ndb instance just to drive the compaction.
        guard let tempNdb = Ndb(path: path) else {
            Log.error("compact_if_needed: failed to open ndb for compaction", for: .storage)
            try? FileManager.default.removeItem(atPath: tempPath)
            return
        }
        // Ensure the temporary Ndb is closed regardless of how this function exits.
        defer { tempNdb.close() }

        do {
            try tempNdb.compact(to: tempPath)
        } catch {
            Log.error("compact_if_needed: compaction failed: %@", for: .storage, String(describing: error))
            try? FileManager.default.removeItem(atPath: tempPath)
            return
        }
        
        tempNdb.close()

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
            return
        }

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
            return
        }

        // Post-replace sanity check: verify the destination file exists with the expected size.
        let finalSize = (try? FileManager.default.attributesOfItem(atPath: originalDataMdb.path)[.size] as? Int) ?? 0
        if finalSize != compactedSize {
            Log.error("compact_if_needed: post-replace size mismatch — expected %d, got %d", for: .storage, compactedSize, finalSize)
            try? FileManager.default.removeItem(atPath: tempPath)
            return
        }

        Log.info("NostrDB compacted successfully", for: .storage)

        // Clean up the temp directory (any remaining files such as lock.mdb).
        try? FileManager.default.removeItem(atPath: tempPath)

        // Clear the flag so we don't compact again on the next launch.
        UserDefaults.standard.set(false, forKey: compact_on_next_launch_key)
    }
}
