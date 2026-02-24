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
    
    // MARK: - Static Startup Methods
    
    /// Check if compaction was requested and swap the database if ready.
    ///
    /// This should be called at app startup before initializing the main database.
    /// If a compacted database is ready, this method will atomically replace the
    /// main database with the compacted version.
    ///
    /// - Returns: `true` if a database swap occurred, `false` otherwise
    static func swapDatabaseIfReady() -> Bool {
        guard UserDefaults.standard.bool(forKey: compactionRequestedKey) else {
            return false
        }
        
        guard let compactedPath = UserDefaults.standard.string(forKey: compactedDatabasePathKey) else {
            Log.info("Compaction requested but no compacted database path found", for: .storage)
            UserDefaults.standard.removeObject(forKey: compactionRequestedKey)
            return false
        }
        
        guard let mainDbPath = Ndb.db_path else {
            Log.error("Could not determine main database path", for: .storage)
            return false
        }
        
        let fileManager = FileManager.default
        
        // Verify compacted database exists
        guard fileManager.fileExists(atPath: compactedPath) else {
            Log.info("Compacted database not found at %{public}@", for: .storage, compactedPath)
            UserDefaults.standard.removeObject(forKey: compactionRequestedKey)
            UserDefaults.standard.removeObject(forKey: compactedDatabasePathKey)
            return false
        }
        
        Log.info("Swapping database: %{public}@ -> %{public}@", for: .storage, compactedPath, mainDbPath)
        
        do {
            // Backup old database before replacing
            let backupPath = mainDbPath + ".backup"
            if fileManager.fileExists(atPath: backupPath) {
                try fileManager.removeItem(atPath: backupPath)
            }
            
            // Move old database to backup
            if fileManager.fileExists(atPath: mainDbPath) {
                try fileManager.moveItem(atPath: mainDbPath, toPath: backupPath)
                Log.debug("Backed up old database to %{public}@", for: .storage, backupPath)
            }
            
            // Move compacted database to main location
            try fileManager.moveItem(atPath: compactedPath, toPath: mainDbPath)
            Log.info("Database swap completed successfully", for: .storage)
            
            // Clean up backup after successful swap
            try? fileManager.removeItem(atPath: backupPath)
            
            // Clear the compaction request flags
            UserDefaults.standard.removeObject(forKey: compactionRequestedKey)
            UserDefaults.standard.removeObject(forKey: compactedDatabasePathKey)
            
            return true
        } catch {
            Log.error("Failed to swap database: %{public}@", for: .storage, error.localizedDescription)
            
            // Attempt to restore backup if swap failed
            let backupPath = mainDbPath + ".backup"
            if fileManager.fileExists(atPath: backupPath) && !fileManager.fileExists(atPath: mainDbPath) {
                try? fileManager.moveItem(atPath: backupPath, toPath: mainDbPath)
                Log.info("Restored database from backup after failed swap", for: .storage)
            }
            
            return false
        }
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
