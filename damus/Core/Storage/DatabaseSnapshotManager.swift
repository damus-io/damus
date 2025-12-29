//
//  DatabaseSnapshotManager.swift
//  damus
//
//  Created on 2025-01-20.
//

import Foundation
import OSLog

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
    
    /// Key for storing last snapshot timestamp in UserDefaults
    private static let lastSnapshotDateKey = "lastDatabaseSnapshotDate"
    
    private let ndb: Ndb
    private var snapshotTimerTask: Task<Void, Never>? = nil
    var snapshotTimerTickCount: Int = 0
    var snapshotCount: Int = 0
    
    /// Initialize the snapshot manager with a NostrDB instance
    /// - Parameter ndb: The NostrDB instance to snapshot
    init(ndb: Ndb) {
        self.ndb = ndb
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
    func performSnapshot() async throws {
        guard let snapshotPath = Ndb.snapshot_db_path else {
            throw SnapshotError.pathsUnavailable
        }
        
        Log.info("Starting nostrdb snapshot to %{public}@", for: .storage, snapshotPath)
        
        try await copyDatabase(to: snapshotPath)
        
        // Update the last snapshot date
        UserDefaults.standard.set(Date(), forKey: Self.lastSnapshotDateKey)
        
        Log.info("Database snapshot completed successfully", for: .storage)
        self.snapshotCount += 1
    }
    
    /// Copy the database using LMDB's native copy function.    
    private func copyDatabase(to snapshotPath: String) async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let fileManager = FileManager.default
            
            // Delete existing database files at the destination if they exist
            // LMDB creates multiple files (data.mdb, lock.mdb), so we remove the entire directory
            if fileManager.fileExists(atPath: snapshotPath) {
                do {
                    try fileManager.removeItem(atPath: snapshotPath)
                    Log.debug("Removed existing snapshot at %{public}@", for: .storage, snapshotPath)
                } catch {
                    continuation.resume(throwing: SnapshotError.removeFailed(error))
                    return
                }
            }
            
            Log.debug("Recreate the snapshot directory", for: .storage, snapshotPath)
            // Recreate the snapshot directory
            do {
                try fileManager.createDirectory(atPath: snapshotPath, withIntermediateDirectories: true)
            } catch {
                continuation.resume(throwing: SnapshotError.directoryCreationFailed(error))
                return
            }
            
            do {
                try ndb.snapshot(path: snapshotPath)
                continuation.resume(returning: ())
            }
            catch {
                continuation.resume(throwing: SnapshotError.copyFailed(error))
            }
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
        }
    }
}
