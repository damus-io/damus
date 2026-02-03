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

    /// Marker file name indicating a snapshot is complete and safe to read.
    /// Extensions should only open a snapshot if this file exists.
    static let snapshotReadyMarker = "snapshot.ready"
    
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
    ///
    /// Creates a storage-efficient snapshot by creating a new temporary Ndb instance
    /// and selectively copying only the necessary notes (profiles, mute lists, contact lists).
    func performSnapshot() async throws {
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
    /// 1. Creates a temporary Ndb instance in a temp directory
    /// 2. Queries the source database for relevant notes
    /// 3. Writes each note to the temporary database
    /// 4. Atomically moves the temporary database to the final destination
    private func createSelectiveSnapshot(to snapshotPath: String) async throws {
        let fileManager = FileManager.default
        
        // Create a temporary directory for the snapshot
        let tempDir = FileManager.default.temporaryDirectory
        let tempSnapshotPath = tempDir.appendingPathComponent("snapshot_temp_\(UUID().uuidString)")
        
        do {
            try fileManager.createDirectory(atPath: tempSnapshotPath.path, withIntermediateDirectories: true)
        } catch {
            throw SnapshotError.directoryCreationFailed(error)
        }
        
        // Ensure cleanup on error
        defer {
            try? fileManager.removeItem(atPath: tempSnapshotPath.path)
        }
        
        Log.debug("Created temporary snapshot directory at %{public}@", for: .storage, tempSnapshotPath.path)
        
        // Create a new Ndb instance in the temporary directory
        guard let snapshotNdb = Ndb(path: tempSnapshotPath.path, owns_db_file: true) else {
            throw SnapshotError.failedToCreateSnapshotDatabase
        }
        
        defer {
            snapshotNdb.close()
        }
        
        Log.debug("Created temporary Ndb instance for snapshot", for: .storage)
        
        // Query and copy notes to snapshot database
        try await copyNotesToSnapshot(snapshotNdb: snapshotNdb)
        
        Log.debug("Copied notes to snapshot database", for: .storage)
        
        // Close the snapshot database before moving files
        snapshotNdb.close()
        
        // Atomically move the temporary database to the final destination
        try await moveSnapshotToFinalDestination(from: tempSnapshotPath.path, to: snapshotPath)
        
        Log.debug("Moved snapshot to final destination", for: .storage)
    }
    
    /// Queries the source database and copies relevant notes to the snapshot database.
    private func copyNotesToSnapshot(snapshotNdb: Ndb) async throws {
        let filters = try createSnapshotFilters()
        
        Log.debug("Querying source database with %d filters", for: .storage, filters.count)
        
        var totalNotesCopied = 0
        
        for filter in filters {
            let noteKeys = try ndb.query(filters: [filter], maxResults: 100_000)
            
            Log.debug("Found %d notes for filter", for: .storage, noteKeys.count)
            
            for noteKey in noteKeys {
                // Get the note from source database and copy to snapshot
                try ndb.lookup_note_by_key(noteKey, borrow: { unownedNote in
                    // Convert the note to owned, encode to JSON, and process into snapshot database
                    guard let ownedNote = unownedNote?.toOwned() else {
                        Log.error("Failed to get unowned note", for: .storage)
                        return
                    }
                    
                    // Process the note into the snapshot database
                    
                    // Implementation note: This does not _immediately_ add the event to the new Ndb.
                    // It goes into the ingester queue first for later processing.
                    // This raises the question: How to guarantee that all notes will be saved to the new
                    // snapshot Ndb before we close it?
                    //
                    // The answer is that when `Ndb.close` is called, it actually waits for the ingester task
                    // to finish processing its queue — unless the queue is full (an edge case).
                    try snapshotNdb.add(event: ownedNote)
                    totalNotesCopied += 1
                })
            }
        }
        
        Log.info("Copied %d notes to snapshot database", for: .storage, totalNotesCopied)
    }
    
    /// Creates filters for querying profiles, mute lists, and contact lists.
    private func createSnapshotFilters() throws -> [NdbFilter] {
        // Filter for profile metadata (kind 0)
        let profileFilter = try NdbFilter(from: NostrFilter(kinds: [.metadata]))
        
        // Filter for contact lists (kind 3)
        let contactsFilter = try NdbFilter(from: NostrFilter(kinds: [.contacts]))
        
        // Filter for mute lists (kind 10000)
        let muteListFilter = try NdbFilter(from: NostrFilter(kinds: [.mute_list]))
        
        return [profileFilter, contactsFilter, muteListFilter]
    }
    
    /// Atomically moves the snapshot from temporary location to final destination.
    ///
    /// Uses a marker file to signal when the snapshot is complete and safe to read.
    /// Extensions should only open a snapshot when the marker file exists.
    private func moveSnapshotToFinalDestination(from tempPath: String, to finalPath: String) async throws {
        let fileManager = FileManager.default
        let markerPath = URL(fileURLWithPath: finalPath)
            .deletingLastPathComponent()
            .appendingPathComponent(Self.snapshotReadyMarker)
            .path

        // Remove marker first so extensions know snapshot is invalid during transition.
        // This must succeed - if the marker persists, extensions may read corrupt data.
        if fileManager.fileExists(atPath: markerPath) {
            do {
                try fileManager.removeItem(atPath: markerPath)
                Log.debug("Removed snapshot marker before update", for: .storage)
            } catch {
                Log.error("Failed to remove snapshot marker: %{public}@", for: .storage, error.localizedDescription)
                throw SnapshotError.removeFailed(error)
            }
        }

        // Remove existing snapshot if it exists
        if fileManager.fileExists(atPath: finalPath) {
            do {
                try fileManager.removeItem(atPath: finalPath)
                Log.debug("Removed existing snapshot at %{public}@", for: .storage, finalPath)
            } catch {
                throw SnapshotError.removeFailed(error)
            }
        }

        // Create parent directory if needed
        let parentDir = URL(fileURLWithPath: finalPath).deletingLastPathComponent().path
        if !fileManager.fileExists(atPath: parentDir) {
            do {
                try fileManager.createDirectory(atPath: parentDir, withIntermediateDirectories: true)
            } catch {
                throw SnapshotError.directoryCreationFailed(error)
            }
        }

        // Atomically move the temp snapshot to final destination
        do {
            try fileManager.moveItem(atPath: tempPath, toPath: finalPath)
            Log.debug("Moved snapshot from %{public}@ to %{public}@", for: .storage, tempPath, finalPath)
        } catch {
            throw SnapshotError.moveFailed(error)
        }

        // Write marker file to signal snapshot is complete and safe to read
        do {
            try Data().write(to: URL(fileURLWithPath: markerPath))
            Log.debug("Wrote snapshot ready marker at %{public}@", for: .storage, markerPath)
        } catch {
            Log.error("Failed to write snapshot marker: %{public}@", for: .storage, error.localizedDescription)
            // Don't throw - snapshot is valid, marker is just a safety signal
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
