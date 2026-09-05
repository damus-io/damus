//
//  DatabaseSnapshotManager.swift
//  damus
//
//  Created on 2025-01-20.
//

import Foundation
import OSLog
import Sentry

/// Manages periodic snapshots of the main NostrDB database to a shared container location.
///
/// This allows app extensions (like notification service extensions) to access a recent
/// read-only copy of the database for enhanced UX, while the main database resides in
/// the private container to avoid 0xdead10cc crashes and issues related to holding file locks on shared containers.
///
/// Snapshots are created periodically while the app is in the foreground, since the database
/// only gets updated when the app is active.
actor DatabaseSnapshotManager {
    
    /// Minimum interval between snapshots (in seconds)
    private static let minimumSnapshotInterval: TimeInterval = 60 * 60 // 1 hour

    /// Prefix used for temporary directories that stage snapshot databases before promotion.
    private static let temporarySnapshotDirectoryPrefix = "snapshot_temp_"

    /// Maximum age for temporary snapshot directories before they are considered stale.
    private static let staleTemporarySnapshotLifetime: TimeInterval = 60 * 30    // 30 minutes
    
    /// Key for storing last snapshot timestamp in UserDefaults
    private static let lastSnapshotDateKey = "lastDatabaseSnapshotDate"
    
    private let ndb: Ndb

    /// The logged-in user's pubkey.
    ///
    /// Used to scope the personal lists we snapshot to the ones that belong to us. See
    /// `createSnapshotFilters`.
    private let our_pubkey: Pubkey

    private var snapshotTimerTask: Task<Void, Never>? = nil
    var snapshotTimerTickCount: Int = 0
    var snapshotCount: Int = 0
    
    /// Initialize the snapshot manager with a NostrDB instance
    /// - Parameters:
    ///   - ndb: The NostrDB instance to snapshot
    ///   - our_pubkey: The logged-in user's pubkey, used to scope the personal lists we copy
    init(ndb: Ndb, our_pubkey: Pubkey) {
        self.ndb = ndb
        self.our_pubkey = our_pubkey
    }
    
    // MARK: - Periodic tasks management
    
    /// Start the periodic snapshot timer.
    ///
    /// This should be called when the app enters the foreground.
    /// The timer will fire periodically to check if a snapshot is needed.
    func startPeriodicSnapshots() {
        // Don't start if already running
        guard snapshotTimerTask == nil else {
            Log.debug("Snapshot timer already running", for: .storage)
            return
        }
        
        Log.info("Starting periodic database snapshot timer", for: .storage)
        
        snapshotTimerTask = Task(priority: .utility) { [weak self] in
            await self?.cleanupStaleTemporarySnapshots()

            while !Task.isCancelled {
                guard let self else { return }
                Log.debug("Snapshot timer - tick", for: .storage)
                await self.increaseSnapshotTimerTickCount()
                do {
                    try await self.createSnapshotIfNeeded()
                }
                catch {
                    Log.error("Failed to create snapshot: %{public}@", for: .storage, error.localizedDescription)
                }
                try? await Task.sleep(for: .seconds(60 * 5), tolerance: .seconds(10))
            }
        }
    }
    
    /// Stop the periodic snapshot timer.
    ///
    /// This should be called when the app enters the background.
    func stopPeriodicSnapshots() async {
        guard snapshotTimerTask != nil else {
            return
        }
        
        Log.info("Stopping periodic database snapshot timer", for: .storage)
        snapshotTimerTask?.cancel()
        await snapshotTimerTask?.value
        snapshotTimerTask = nil
    }
    
    
    // MARK: - Snapshotting
    
    /// Perform a database snapshot if needed.
    ///
    /// This method checks if enough time has passed since the last snapshot and creates a new one if necessary.
    @discardableResult
    func createSnapshotIfNeeded() async throws -> Bool {
        guard shouldCreateSnapshot() else {
            Log.debug("Skipping snapshot - minimum interval not yet elapsed", for: .storage)
            return false
        }
        
        try await self.performSnapshot()
        return true
    }
    
    /// Check if a snapshot should be created based on the last snapshot time.
    private func shouldCreateSnapshot() -> Bool {
        guard let lastSnapshotDate = UserDefaults.standard.object(forKey: Self.lastSnapshotDateKey) as? Date else {
            return true // No snapshot has been created yet
        }
        
        let timeSinceLastSnapshot = Date().timeIntervalSince(lastSnapshotDate)
        return timeSinceLastSnapshot >= Self.minimumSnapshotInterval
    }
    
    /// Perform the actual snapshot operation.
    ///
    /// Creates a storage-efficient snapshot by creating a new temporary Ndb instance
    /// and selectively copying only the necessary notes (profiles, mute lists, contact lists).
    func performSnapshot() async throws {
        await cleanupStaleTemporarySnapshots()

        guard let snapshotPath = Ndb.snapshot_db_path else {
            throw SnapshotError.pathsUnavailable
        }
        
        Log.info("Starting nostrdb snapshot to %{public}@", for: .storage, snapshotPath)
        
        try await createSelectiveSnapshot(to: snapshotPath)
        
        // Update the last snapshot date
        UserDefaults.standard.set(Date(), forKey: Self.lastSnapshotDateKey)
        
        Log.info("Database snapshot completed successfully", for: .storage)
        self.snapshotCount += 1
    }
    
    /// Creates a selective snapshot containing only profiles, mute lists, and contact lists.
    ///
    /// This method:
    /// 1. Prunes the live database into a temporary directory, keeping only the
    ///    kinds the extensions read
    /// 2. Promotes the temporary database to the final destination
    ///
    /// `ndb_prune` rather than a re-ingest, because the size of this file is the
    /// entire point of it. The snapshot used to be built by opening a second
    /// read-write `Ndb` on a temp directory and pushing every matched note
    /// through `add(event:)`. That hands the ingester tens of thousands of notes
    /// in one burst, and the writer thread commits them in transactions of up to
    /// `THREAD_QUEUE_BATCH` (4096, `nostrdb/src/nostrdb.c:47`). Pages freed
    /// inside a transaction cannot be recycled until it commits, so a burst
    /// ingest sets a high-water mark LMDB never gives back to the filesystem —
    /// measured at 114x file-to-content in headway:damus-ios/jump-glance-orphan,
    /// and on a real phone it turned ~43 MiB of profiles and contact lists into a
    /// 2 GB snapshot.
    ///
    /// `ndb_prune` writes its whole output under a single destination write
    /// transaction (`nostrdb/src/nostrdb.c:9515`), which is why the same
    /// measurement puts it at 1.49x. It also needs no second `Ndb` instance, so
    /// the snapshot no longer depends on an ingester queue draining before the
    /// database it is writing to gets closed.
    private func createSelectiveSnapshot(to snapshotPath: String) async throws {
        let fileManager = FileManager.default

        // Create a temporary directory for the snapshot
        let tempDir = FileManager.default.temporaryDirectory
        let tempSnapshotPath = tempDir.appendingPathComponent("\(Self.temporarySnapshotDirectoryPrefix)\(UUID().uuidString)")
        var didPromoteSnapshot = false

        do {
            // LMDB will not create the destination, and insists on it being empty.
            try fileManager.createDirectory(atPath: tempSnapshotPath.path, withIntermediateDirectories: true)
        } catch {
            DamusSentry.captureSentryError(error) { scope in
                scope.setContext(value: [
                    "operation": "create_temp_snapshot_directory",
                    "path": tempSnapshotPath.path
                ], key: "snapshot")
            }
            throw SnapshotError.directoryCreationFailed(error)
        }

        // Ensure cleanup on error
        defer {
            if !didPromoteSnapshot && fileManager.fileExists(atPath: tempSnapshotPath.path) {
                do {
                    try fileManager.removeItem(atPath: tempSnapshotPath.path)
                } catch {
                    Log.error("Failed to cleanup temporary snapshot directory: %{public}@", for: .storage, error.localizedDescription)
                    DamusSentry.captureSentryError(error) { scope in
                        scope.setContext(value: [
                            "operation": "cleanup_temp_snapshot_directory",
                            "path": tempSnapshotPath.path
                        ], key: "snapshot")
                    }
                }
            }
        }

        Log.debug("Created temporary snapshot directory at %{public}@", for: .storage, tempSnapshotPath.path)

        let report = try await self.pruneIntoSnapshot(at: tempSnapshotPath.path)

        Log.info("Snapshot prune %{public}@", for: .storage, report.summary)

        // Promote the temporary database to the final destination
        try await moveSnapshotToFinalDestination(from: tempSnapshotPath.path, to: snapshotPath)
        didPromoteSnapshot = true

        Log.debug("Moved snapshot to final destination", for: .storage)
    }

    /// Prunes the live database into `path`, keeping only what the extensions read.
    ///
    /// `dedupeReplaceable` is left on: every kind the snapshot keeps is a
    /// replaceable event, and nostrdb stores each version it has ever seen as its
    /// own note. Without it a snapshot carries every historical profile and every
    /// superseded contact list — on one real database, 51,226 kind-0 notes for
    /// 39,499 pubkeys, and 181 contact lists for a single author. An extension
    /// only ever wants the current version of any of them.
    private func pruneIntoSnapshot(at path: String) async throws -> NdbPruneReport {
        let filters = try createSnapshotFilters()
        let ndb = self.ndb

        do {
            return try await Self.offCooperativePool({
                // `filters` owns the allocations the C structs point into, so it
                // has to outlive the prune rather than just its last use.
                try withExtendedLifetime(filters, {
                    try ndb.prune(to: path, filters: filters)
                })
            })
        } catch {
            DamusSentry.captureSentryError(error) { scope in
                var context: [String: String] = ["operation": "prune_snapshot", "path": path]
                if let pruneError = error as? NdbPruneError {
                    context.merge(pruneError.reportContext, uniquingKeysWith: { current, _ in current })
                }
                scope.setContext(value: context, key: "snapshot")
            }
            throw error
        }
    }

    /// Runs blocking nostrdb work off the cooperative thread pool.
    ///
    /// A prune blocks the thread it runs on, and Swift's cooperative pool has one
    /// thread per core to spare, so running it there would stall unrelated work.
    /// The same reasoning, and the same shape, as `NdbPruneManager.offMainPool`.
    private static func offCooperativePool<T>(_ work: @escaping () throws -> T) async throws -> T {
        return try await withCheckedThrowingContinuation({ continuation in
            snapshotQueue.async {
                continuation.resume(with: Result(catching: work))
            }
        })
    }

    private static let snapshotQueue = DispatchQueue(label: "com.jb55.damus.ndb-snapshot", qos: .utility)
    
    /// Creates filters for querying profiles, and our own mute list and contact list.
    private func createSnapshotFilters() throws -> [NdbFilter] {
        // Filter for profile metadata (kind 0). Any pubkey's profile can turn up as the sender of
        // a push notification or as a mention being rendered, so these are not scoped to us.
        let profileFilter = try NdbFilter(from: NostrFilter(kinds: [.metadata]))
        
        // Contact lists (kind 3) and mute lists (kind 10000) are only ever consulted for the
        // logged-in user — "is this note from someone I follow" and "is this note muted". Other
        // people's lists are dead weight in the snapshot, and expensive dead weight: a contact
        // list costs roughly 90 bytes per follow once the tag index is counted, so a database
        // that has cached a few hundred of them contributes tens of megabytes that nothing in
        // any extension reads. Scope both to our own pubkey.
        let contactsFilter = try NdbFilter(from: NostrFilter(kinds: [.contacts], authors: [our_pubkey]))
        
        let muteListFilter = try NdbFilter(from: NostrFilter(kinds: [.mute_list], authors: [our_pubkey]))
        
        return [profileFilter, contactsFilter, muteListFilter]
    }
    
    /// Removes stale temporary snapshot directories left behind by interrupted snapshot attempts.
    private func cleanupStaleTemporarySnapshots(now: Date = Date()) {
        let fileManager = FileManager.default
        let tempDir = fileManager.temporaryDirectory

        do {
            let tempEntries = try fileManager.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            )

            for tempEntry in tempEntries {
                guard tempEntry.lastPathComponent.hasPrefix(Self.temporarySnapshotDirectoryPrefix) else {
                    continue
                }

                let resourceValues = try tempEntry.resourceValues(forKeys: [.isDirectoryKey, .contentModificationDateKey, .creationDateKey])

                guard resourceValues.isDirectory == true else {
                    continue
                }

                let referenceDate = resourceValues.contentModificationDate ?? resourceValues.creationDate
                guard let referenceDate else {
                    continue
                }

                guard now.timeIntervalSince(referenceDate) >= Self.staleTemporarySnapshotLifetime else {
                    continue
                }

                do {
                    try fileManager.removeItem(at: tempEntry)
                    Log.info("Removed stale temporary snapshot directory at %{public}@", for: .storage, tempEntry.path)
                } catch {
                    Log.error("Failed to cleanup stale temporary snapshot directory: %{public}@", for: .storage, error.localizedDescription)
                }
            }
        } catch {
            Log.error("Failed to enumerate temporary snapshot directories: %{public}@", for: .storage, error.localizedDescription)
        }
    }

    /// Promotes the snapshot from temporary location to final destination without deleting the current snapshot first.
    private func moveSnapshotToFinalDestination(from tempPath: String, to finalPath: String) async throws {
        let fileManager = FileManager.default
        let finalURL = URL(fileURLWithPath: finalPath, isDirectory: true)
        let tempURL = URL(fileURLWithPath: tempPath, isDirectory: true)
        
        // Create parent directory if needed
        let parentDir = finalURL.deletingLastPathComponent().path
        if !fileManager.fileExists(atPath: parentDir) {
            do {
                try fileManager.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            } catch {
                DamusSentry.captureSentryError(error) { scope in
                    scope.setContext(value: [
                        "operation": "create_parent_directory",
                        "path": parentDir
                    ], key: "snapshot")
                }
                throw SnapshotError.directoryCreationFailed(error)
            }
        }
        
        // Replace the existing snapshot only after the staged snapshot is ready.
        do {
            if fileManager.fileExists(atPath: finalPath) {
                _ = try fileManager.replaceItemAt(finalURL, withItemAt: tempURL, backupItemName: nil, options: [.usingNewMetadataOnly])
            } else {
                try fileManager.moveItem(at: tempURL, to: finalURL)
            }

            Log.debug("Moved snapshot from %{public}@ to %{public}@", for: .storage, tempPath, finalPath)
        } catch {
            DamusSentry.captureSentryError(error) { scope in
                scope.setContext(value: [
                    "operation": "move_snapshot_to_final_destination",
                    "temp_path": tempPath,
                    "final_path": finalPath,
                    "file_exists": fileManager.fileExists(atPath: finalPath)
                ], key: "snapshot")
            }
            throw SnapshotError.moveFailed(error)
        }
    }
    
    // MARK: - Stats functions
    
    private func increaseSnapshotTimerTickCount() async {
        self.snapshotTimerTickCount += 1
    }
    
    func resetStats() async {
        self.snapshotTimerTickCount = 0
        self.snapshotCount = 0
    }
}

// MARK: - Error Types

enum SnapshotError: Error, LocalizedError {
    case pathsUnavailable
    case copyFailed(any Error)
    case removeFailed(Error)
    case directoryCreationFailed(Error)
    case failedToCreateSnapshotDatabase
    case moveFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .pathsUnavailable:
            return "Database paths are not available"
        case .copyFailed(let code):
            return "Failed to copy database (error code: \(code))"
        case .removeFailed(let error):
            return "Failed to remove existing snapshot: \(error.localizedDescription)"
        case .directoryCreationFailed(let error):
            return "Failed to create snapshot directory: \(error.localizedDescription)"
        case .failedToCreateSnapshotDatabase:
            return "Failed to create temporary snapshot database"
        case .moveFailed(let error):
            return "Failed to move snapshot to final destination: \(error.localizedDescription)"
        }
    }
}
