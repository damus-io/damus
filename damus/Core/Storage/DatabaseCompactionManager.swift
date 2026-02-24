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
    private let damusState: DamusState
    
    /// Current compaction task, if one is running
    private var compactionTask: Task<Void, Error>? = nil
    
    /// Initialize the compaction manager
    /// - Parameters:
    ///   - ndb: The NostrDB instance to compact
    ///   - damusState: The app state containing user keypairs
    init(ndb: Ndb, damusState: DamusState) {
        self.ndb = ndb
        self.damusState = damusState
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
    /// - Throws: `CompactionError` if compaction fails
    func performCompaction() async throws {
        guard !isCompacting() else {
            Log.info("Compaction already in progress", for: .storage)
            return
        }
        
        Log.info("Starting database compaction", for: .storage)
        
        compactionTask = Task {
            try await self.performCompactionInternal()
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
    private func performCompactionInternal() async throws {
        let fileManager = FileManager.default
        
        // Create a temporary directory for the compacted database
        let tempDir = FileManager.default.temporaryDirectory
        let tempCompactPath = tempDir.appendingPathComponent("compacted_db_\(UUID().uuidString)")
        
        // Ensure cleanup on error
        defer {
            try? fileManager.removeItem(atPath: tempCompactPath.path)
        }
        
        do {
            try fileManager.createDirectory(atPath: tempCompactPath.path, withIntermediateDirectories: true)
        } catch {
            throw CompactionError.directoryCreationFailed(error)
        }
        
        Log.debug("Created temporary compaction directory at %{public}@", for: .storage, tempCompactPath.path)
        
        // Collect all user pubkeys
        let pubkeys = collectUserPubkeys()
        
        guard !pubkeys.isEmpty else {
            throw CompactionError.noPubkeysAvailable
        }
        
        Log.info("Compacting database for %d pubkey(s)", for: .storage, pubkeys.count)
        
        // Perform the compaction using ndb_compact
        do {
            try ndb.compact(outputPath: tempCompactPath.path, ownPubkeys: pubkeys)
        } catch {
            throw CompactionError.compactionFailed(error)
        }
        
        Log.info("Database compaction completed successfully", for: .storage)
        
        // Store the compacted database path for swap on next launch
        UserDefaults.standard.set(tempCompactPath.path, forKey: Self.compactedDatabasePathKey)
        
        // Don't delete the temp dir in defer since we're keeping it for swap
        fileManager.stopAccessingSecurityScopedResource()
    }
    
    /// Collect all user public keys from the app state.
    ///
    /// - Returns: Array of 32-byte public keys
    private func collectUserPubkeys() -> [[UInt8]] {
        var pubkeys: [[UInt8]] = []
        
        // Add main account pubkey if available
        if let mainPubkey = damusState.keypair.pubkey_bytes {
            pubkeys.append(Array(mainPubkey))
        }
        
        // Add all logged-in account pubkeys
        for keypair in damusState.login_manager.getKeypairs() {
            if let pubkeyBytes = keypair.pubkey_bytes {
                pubkeys.append(Array(pubkeyBytes))
            }
        }
        
        // Deduplicate pubkeys
        var uniquePubkeys: [[UInt8]] = []
        var seenPubkeys: Set<[UInt8]> = []
        
        for pubkey in pubkeys {
            if !seenPubkeys.contains(pubkey) {
                seenPubkeys.insert(pubkey)
                uniquePubkeys.append(pubkey)
            }
        }
        
        return uniquePubkeys
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
