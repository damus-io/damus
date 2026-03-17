//
//  Ndb+Purge.swift
//  damus
//

import Foundation

extension Ndb {
    /// The `UserDefaults` key used to signal that the database should be purged on the next app launch.
    static let purge_on_next_launch_key = "ndb_purge_on_next_launch"

    /// Requests that the database be purged the next time the app launches.
    ///
    /// Call this to schedule a one-time purge. The flag is cleared automatically
    /// after the purge completes in `purge_if_needed()`.
    static func set_purge_on_next_launch() {
        UserDefaults.standard.set(true, forKey: purge_on_next_launch_key)
    }

    /// The `UserDefaults` key used by `DatabaseSnapshotManager` to record
    /// the last snapshot timestamp.  Cleared during purge so the snapshot
    /// manager rebuilds immediately on the next launch.
    private static let lastSnapshotDateKey = "lastDatabaseSnapshotDate"

    /// The `UserDefaults` key used by `Drafts` to store NIP-37 draft event IDs.
    /// Cleared during purge because the draft notes only exist in NostrDB.
    private static let draftEventIdsKey = "draft_event_ids"

    /// Purges the NostrDB database files and all caches if the purge-on-next-launch flag is set.
    ///
    /// This is intended to be called once during app startup **before** `compact_if_needed()`
    /// and before `Ndb` is opened for normal use. The algorithm is:
    ///   1. Delete `data.mdb` and `lock.mdb` at the database path.
    ///   2. Delete snapshot database files so the notification extension doesn't use stale data.
    ///   3. Clear the snapshot freshness timestamp so a new snapshot is created immediately.
    ///   4. Clean up any leftover compaction temp directory.
    ///   5. Clear app Caches directory contents (video cache, relay logs, etc.).
    ///   6. Clear Kingfisher image cache in the shared app group container.
    ///   7. Clear temporary directory contents (stale temp media files).
    ///   8. Clear both the purge flag and the compact flag (compaction is pointless after a purge).
    ///
    /// - Parameters:
    ///   - db_path: Override the database directory path. Pass `nil` (default) to use
    ///     `Ndb.db_path`. Mainly useful for testing.
    ///   - snapshot_db_path: Override the snapshot directory path. Pass `nil` (default) to use
    ///     `Ndb.snapshot_db_path`. Mainly useful for testing.
    ///   - caches_dir_path: Override the app Caches directory path. Pass `nil` (default) to use
    ///     the system Caches directory. Mainly useful for testing.
    ///   - app_group_cache_path: Override the app group ImageCache directory path. Pass `nil`
    ///     (default) to derive from the app group container. Mainly useful for testing.
    ///   - temp_dir_path: Override the temporary directory path. Pass `nil` (default) to use
    ///     `NSTemporaryDirectory()`. Mainly useful for testing.
    static func purge_if_needed(
        db_path: String? = nil,
        snapshot_db_path: String? = nil,
        caches_dir_path: String? = nil,
        app_group_cache_path: String? = nil,
        temp_dir_path: String? = nil
    ) {
        guard UserDefaults.standard.bool(forKey: purge_on_next_launch_key) else { return }

        guard let path = db_path ?? Self.db_path else {
            Log.error("purge_if_needed: could not determine db path", for: .storage)
            return
        }

        Log.info("Purging NostrDB on startup…", for: .storage)

        let file_manager = FileManager.default

        // Delete main database files (data.mdb and lock.mdb)
        if Self.db_file_exists(path: path) {
            for db_file in db_files {
                try? file_manager.removeItem(atPath: "\(path)/\(db_file)")
            }
        }

        // Delete snapshot database files so the notification extension doesn't use stale data
        let effective_snapshot_path = snapshot_db_path ?? Self.snapshot_db_path
        if let effective_snapshot_path {
            for db_file in db_files {
                try? file_manager.removeItem(atPath: "\(effective_snapshot_path)/\(db_file)")
            }
        }

        // Clear the snapshot freshness timestamp so DatabaseSnapshotManager
        // rebuilds immediately instead of skipping for up to an hour.
        UserDefaults.standard.removeObject(forKey: lastSnapshotDateKey)

        // Clear draft event IDs — the NIP-37 draft notes they reference
        // are stored only in NostrDB and will be destroyed by the purge.
        UserDefaults.standard.removeObject(forKey: draftEventIdsKey)

        // Clean up any leftover compaction temp directory
        let compact_temp_path = "\(path)/ndb_compact_temp"
        try? file_manager.removeItem(atPath: compact_temp_path)

        // Clear app Caches directory contents (video cache, relay logs, etc.)
        let effective_caches_path = caches_dir_path
            ?? file_manager.urls(for: .cachesDirectory, in: .userDomainMask).first?.path
        if let effective_caches_path {
            clear_directory_contents(effective_caches_path, label: "Caches", file_manager: file_manager)
        }

        // Clear Kingfisher image cache in the shared app group container
        let effective_app_group_cache_path = app_group_cache_path
            ?? file_manager.containerURL(forSecurityApplicationGroupIdentifier: "group.com.damus")?
                .appendingPathComponent("Library/Caches/ImageCache").path
        if let effective_app_group_cache_path {
            clear_directory_contents(effective_app_group_cache_path, label: "AppGroup ImageCache", file_manager: file_manager)
        }

        // Clear temporary directory contents (stale temp media files)
        let effective_temp_path = temp_dir_path ?? NSTemporaryDirectory()
        clear_directory_contents(effective_temp_path, label: "Temp", file_manager: file_manager)

        Log.info("NostrDB purged successfully", for: .storage)

        // Clear both the purge flag and the compact flag (compaction is pointless after a purge)
        UserDefaults.standard.set(false, forKey: purge_on_next_launch_key)
        UserDefaults.standard.set(false, forKey: compact_on_next_launch_key)
    }

    /// Remove all children of a directory without deleting the directory itself.
    private static func clear_directory_contents(_ path: String, label: String, file_manager: FileManager) {
        guard file_manager.fileExists(atPath: path) else { return }
        do {
            let children = try file_manager.contentsOfDirectory(atPath: path)
            for child in children {
                try? file_manager.removeItem(atPath: "\(path)/\(child)")
            }
            Log.info("Cleared %@ directory contents (%d items)", for: .storage, label, children.count)
        } catch {
            Log.error("Failed to enumerate %@ directory: %@", for: .storage, label, error.localizedDescription)
        }
    }
}
