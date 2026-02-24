//
//  DatabaseCompactionManager.swift
//  damus
//
//  Created on 2025-02-23.
//

import Foundation
import OSLog

/// Manages database compaction operations to reclaim storage space.
///
/// Compaction creates a new database containing only:
/// - All profiles (kind 0 notes)
/// - Notes authored by the user's own public keys
/// - Profile last-fetch metadata
///
/// All other notes (replies, reposts, reactions from others) are discarded.
/// This is useful for users who want to preserve their own content while
/// freeing up space used by other people's notes.
actor DatabaseCompactionManager {
    
    /// Key for storing compaction request flag in UserDefaults
    private static let compactionRequestedKey = "databaseCompactionRequested"
    
    /// Key for storing compacted database path in UserDefaults
    private static let compactedDatabasePathKey = "compactedDatabasePath"
    
    private let ndb: Ndb
    
    /// Current compaction task, if one is running
    private var compactionTask: Task<Void, Error>? = nil
    
    /// Initialize the compaction manager
    /// - Parameter ndb: The NostrDB instance to compact
    init(ndb: Ndb) {
        self.ndb = ndb
    }
    
    // MARK: - Public API
    
    /// Request a database compaction to be performed on next app launch.
    ///
    /// This sets a flag that will be checked during app startup. The compaction
    /// will be performed in the background, and the app will swap to the compacted
    /// database once it's ready.
    func requestCompaction() {
        UserDefaults.standard.set(true, forKey: Self.compactionRequestedKey)
        Log.info("Database compaction requested for next launch", for: .storage)
    }
    
    /// Check if a compaction has been requested.
    func isCompactionRequested() -> Bool {
        return UserDefaults.standard.bool(forKey: Self.compactionRequestedKey)
    }
    
    /// Check if a compaction is currently in progress.
    func isCompacting() -> Bool {
        return compactionTask != nil && !(compactionTask?.isCancelled ?? true)
    }
    
    /// Get the path to a completed compacted database, if one exists.
    func getCompactedDatabasePath() -> String? {
        return UserDefaults.standard.string(forKey: Self.compactedDatabasePathKey)
    }
    
    /// Start the compaction process.
    ///
    /// This performs the compaction in the background and stores the path
    /// to the compacted database in UserDefaults when complete.
    ///
    /// - Parameter ownPubkeys: Array of 32-byte public keys whose notes should be retained
    /// - Throws: `CompactionError` if compaction fails
    func performCompaction(ownPubkeys: [[UInt8]]) async throws {
        guard !isCompacting() else {
            Log.info("Compaction already in progress", for: .storage)
            return
        }
        
        Log.info("Starting database compaction", for: .storage)
        
        compactionTask = Task {
            try await self.performCompactionInternal(ownPubkeys: ownPubkeys)
        }
        
        try await compactionTask?.value
        compactionTask = nil
    }
    
    /// Clear the compaction request flag and any stored compacted database path.
    func clearCompactionRequest() {
        UserDefaults.standard.removeObject(forKey: Self.compactionRequestedKey)
        UserDefaults.standard.removeObject(forKey: Self.compactedDatabasePathKey)
        Log.debug("Cleared compaction request flag", for: .storage)
    }
    
    /// Remove the compacted database file if it exists.
    func cleanupCompactedDatabase() throws {
        guard let compactedPath = getCompactedDatabasePath() else {
            return
        }
        
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: compactedPath) {
            do {
                try fileManager.removeItem(atPath: compactedPath)
                Log.info("Removed compacted database at %{public}@", for: .storage, compactedPath)
            } catch {
                throw CompactionError.cleanupFailed(error)
            }
        }
        
        clearCompactionRequest()
    }
    
    // MARK: - Internal Implementation
    
    /// Internal compaction logic.
    /// - Parameter ownPubkeys: Array of 32-byte public keys whose notes should be retained
    private func performCompactionInternal(ownPubkeys: [[UInt8]]) async throws {
        let fileManager = FileManager.default
        
        // Create a temporary directory for the compacted database
        let tempDir = FileManager.default.temporaryDirectory
        let tempCompactPath = tempDir.appendingPathComponent("compacted_db_\(UUID().uuidString)")
        
        var shouldCleanup = true
        
        // Ensure cleanup on error
        defer {
            if shouldCleanup {
                try? fileManager.removeItem(atPath: tempCompactPath.path)
            }
        }
        
        do {
            try fileManager.createDirectory(atPath: tempCompactPath.path, withIntermediateDirectories: true)
        } catch {
            throw CompactionError.directoryCreationFailed(error)
        }
        
        Log.debug("Created temporary compaction directory at %{public}@", for: .storage, tempCompactPath.path)
        
        guard !ownPubkeys.isEmpty else {
            throw CompactionError.noPubkeysAvailable
        }
        
        Log.info("Compacting database for %d pubkey(s)", for: .storage, ownPubkeys.count)
        
        // Perform the compaction using ndb_compact
        do {
            try ndb.compact(outputPath: tempCompactPath.path, ownPubkeys: ownPubkeys)
        } catch {
            throw CompactionError.compactionFailed(error)
        }
        
        Log.info("Database compaction completed successfully", for: .storage)
        
        // Store the compacted database path for swap on next launch
        UserDefaults.standard.set(tempCompactPath.path, forKey: Self.compactedDatabasePathKey)
        
        // Don't delete the temp dir on success since we're keeping it for swap
        shouldCleanup = false
    }
}

// MARK: - Error Types

enum CompactionError: Error, LocalizedError {
    case directoryCreationFailed(Error)
    case noPubkeysAvailable
    case compactionFailed(Error)
    case cleanupFailed(Error)
    
    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed(let error):
            return "Failed to create compaction directory: \(error.localizedDescription)"
        case .noPubkeysAvailable:
            return "No user public keys available for compaction"
        case .compactionFailed(let error):
            return "Database compaction failed: \(error.localizedDescription)"
        case .cleanupFailed(let error):
            return "Failed to clean up compacted database: \(error.localizedDescription)"
        }
    }
}
