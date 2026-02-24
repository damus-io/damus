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
    
    /// Key for storing compacted database relative path in UserDefaults
    private static let compactedDatabasePathKey = "compactedDatabasePath"
    
    /// Relative directory name for compacted database (within Documents directory)
    private static let compactedDatabaseDirName = "compacted_db_temp"
    
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
        
        guard let compactedRelativePath = UserDefaults.standard.string(forKey: compactedDatabasePathKey) else {
            Log.info("Compaction requested but no compacted database path found", for: .storage)
            UserDefaults.standard.removeObject(forKey: compactionRequestedKey)
            return false
        }
        
        guard let mainDbPath = Ndb.db_path else {
            Log.error("Could not determine main database path", for: .storage)
            return false
        }
        
        let fileManager = FileManager.default
        
        // Resolve the compacted database path relative to current documents directory
        guard let docsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            Log.error("Could not access documents directory during swap", for: .storage)
            UserDefaults.standard.removeObject(forKey: compactionRequestedKey)
            UserDefaults.standard.removeObject(forKey: compactedDatabasePathKey)
            return false
        }
        
        let compactedPath = docsDir.appendingPathComponent(compactedRelativePath).path
        
        Log.info("Resolved compacted database path: %{public}@", for: .storage, compactedPath)
        
        // Verify compacted database exists
        guard fileManager.fileExists(atPath: compactedPath) else {
            Log.info("Compacted database not found at %{public}@", for: .storage, compactedPath)
            UserDefaults.standard.removeObject(forKey: compactionRequestedKey)
            UserDefaults.standard.removeObject(forKey: compactedDatabasePathKey)
            return false
        }
        
        Log.info("Swapping database files from %{public}@ to %{public}@", for: .storage, compactedPath, mainDbPath)
        
        do {
            // Swap each database file individually (data.mdb, lock.mdb)
            for dbFile in Ndb.db_files {
                let sourceFile = (compactedPath as NSString).appendingPathComponent(dbFile)
                let destFile = (mainDbPath as NSString).appendingPathComponent(dbFile)
                let backupFile = destFile + ".backup"
                
                // Verify source file exists
                guard fileManager.fileExists(atPath: sourceFile) else {
                    Log.info("Source database file not found: %{public}@", for: .storage, sourceFile)
                    continue
                }
                
                Log.debug("Swapping file: %{public}@", for: .storage, dbFile)
                
                // Remove old backup if exists
                if fileManager.fileExists(atPath: backupFile) {
                    try fileManager.removeItem(atPath: backupFile)
                }
                
                // Backup current file if it exists
                if fileManager.fileExists(atPath: destFile) {
                    try fileManager.moveItem(atPath: destFile, toPath: backupFile)
                    Log.debug("Backed up %{public}@ to backup", for: .storage, dbFile)
                }
                
                // Move compacted file to main location
                try fileManager.moveItem(atPath: sourceFile, toPath: destFile)
                Log.debug("Moved compacted %{public}@ to main location", for: .storage, dbFile)
                
                // Clean up backup after successful swap
                try? fileManager.removeItem(atPath: backupFile)
            }
            
            // Remove the now-empty compacted database directory
            try? fileManager.removeItem(atPath: compactedPath)
            
            Log.info("Database swap completed successfully", for: .storage)
            
            // Clear the compaction request flags
            UserDefaults.standard.removeObject(forKey: compactionRequestedKey)
            UserDefaults.standard.removeObject(forKey: compactedDatabasePathKey)
            
            return true
        } catch {
            Log.error("Failed to swap database: %{public}@", for: .storage, error.localizedDescription)
            
            // Attempt to restore backups if swap failed
            for dbFile in Ndb.db_files {
                let destFile = (mainDbPath as NSString).appendingPathComponent(dbFile)
                let backupFile = destFile + ".backup"
                
                if fileManager.fileExists(atPath: backupFile) && !fileManager.fileExists(atPath: destFile) {
                    try? fileManager.moveItem(atPath: backupFile, toPath: destFile)
                    Log.info("Restored %{public}@ from backup after failed swap", for: .storage, dbFile)
                }
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
        
        Log.info("performCompactionInternal: starting with %d pubkeys", for: .storage, ownPubkeys.count)
        
        // Create a directory for the compacted database in documents directory (persistent across launches)
        guard let docsDir = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            Log.error("performCompactionInternal: could not access documents directory", for: .storage)
            throw CompactionError.directoryCreationFailed(NSError(domain: "DatabaseCompactionManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not access documents directory"]))
        }
        
        let compactedDbDir = docsDir.appendingPathComponent(Self.compactedDatabaseDirName)
        
        Log.info("performCompactionInternal: compacted db will be at %{public}@", for: .storage, compactedDbDir.path)
        
        var shouldCleanup = true
        
        // Ensure cleanup on error
        defer {
            if shouldCleanup {
                Log.info("performCompactionInternal: cleaning up compacted db (error occurred)", for: .storage)
                try? fileManager.removeItem(at: compactedDbDir)
            } else {
                Log.info("performCompactionInternal: keeping compacted db for swap", for: .storage)
            }
        }
        
        // Remove any existing compacted database directory
        if fileManager.fileExists(atPath: compactedDbDir.path) {
            Log.info("performCompactionInternal: removing existing compacted db", for: .storage)
            try? fileManager.removeItem(at: compactedDbDir)
        }
        
        do {
            try fileManager.createDirectory(at: compactedDbDir, withIntermediateDirectories: true)
            Log.debug("Created compaction directory at %{public}@", for: .storage, compactedDbDir.path)
        } catch {
            Log.error("performCompactionInternal: failed to create directory: %{public}@", for: .storage, error.localizedDescription)
            throw CompactionError.directoryCreationFailed(error)
        }
        
        guard !ownPubkeys.isEmpty else {
            Log.error("performCompactionInternal: no pubkeys provided", for: .storage)
            throw CompactionError.noPubkeysAvailable
        }
        
        Log.info("Compacting database for %d pubkey(s)", for: .storage, ownPubkeys.count)
        
        // Perform the compaction using ndb_compact
        do {
            Log.info("performCompactionInternal: calling ndb.compact()", for: .storage)
            try ndb.compact(outputPath: compactedDbDir.path, ownPubkeys: ownPubkeys)
            Log.info("performCompactionInternal: ndb.compact() returned successfully", for: .storage)
        } catch {
            Log.error("performCompactionInternal: ndb.compact() failed: %{public}@", for: .storage, error.localizedDescription)
            throw CompactionError.compactionFailed(error)
        }
        
        // Verify the compacted database was actually created
        let dataFile = compactedDbDir.appendingPathComponent("data.mdb")
        guard fileManager.fileExists(atPath: dataFile.path) else {
            Log.error("performCompactionInternal: data.mdb not found after compaction", for: .storage)
            throw CompactionError.compactionFailed(NSError(domain: "DatabaseCompactionManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Compacted database file not found"]))
        }
        
        Log.info("Database compaction completed successfully", for: .storage)
        
        // Store the relative path (just the directory name) for swap on next launch
        // This allows the path to be resolved relative to the documents directory at swap time,
        // avoiding issues with the app container UUID changing between launches
        UserDefaults.standard.set(Self.compactedDatabaseDirName, forKey: Self.compactedDatabasePathKey)
        Log.info("performCompactionInternal: stored relative path in UserDefaults: %{public}@", for: .storage, Self.compactedDatabaseDirName)
        
        // Don't delete the compacted db on success since we're keeping it for swap
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
