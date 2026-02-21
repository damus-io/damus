//
//  StorageStatsManager.swift
//  damus
//
//  Created by Daniel D’Aquino on 2026-02-20.
//

import Foundation
import Kingfisher

/// Storage statistics for various Damus data stores
struct StorageStats {
    /// Size of the main NostrDB database file in bytes
    let nostrdbSize: UInt64
    
    /// Size of the snapshot NostrDB database file in bytes
    let snapshotSize: UInt64
    
    /// Size of the Kingfisher image cache in bytes
    let imageCacheSize: UInt64
    
    /// Total storage used across all data stores
    var totalSize: UInt64 {
        return nostrdbSize + snapshotSize + imageCacheSize
    }
    
    /// Calculate the percentage of total storage used by a specific size
    /// - Parameter size: The size to calculate percentage for
    /// - Returns: Percentage value between 0.0 and 100.0
    func percentage(for size: UInt64) -> Double {
        guard totalSize > 0 else { return 0.0 }
        return Double(size) / Double(totalSize) * 100.0
    }
}

/// Manager for calculating storage statistics across Damus data stores
struct StorageStatsManager {
    static let shared = StorageStatsManager()
    
    private init() {}
    
    /// Calculate storage statistics for all Damus data stores
    ///
    /// This method runs all file operations on a background thread to avoid blocking
    /// the main thread. It calculates:
    /// - NostrDB database file size
    /// - Snapshot database file size
    /// - Kingfisher image cache size
    ///
    /// - Returns: StorageStats containing all calculated sizes
    /// - Throws: Error if critical file operations fail
    func calculateStorageStats() async throws -> StorageStats {
        // Run all file operations on background thread
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let nostrdbSize = self.getNostrDBSize()
                    let snapshotSize = self.getSnapshotDBSize()
                    
                    // Kingfisher cache size requires async callback
                    KingfisherManager.shared.cache.calculateDiskStorageSize { result in
                        let imageCacheSize: UInt64
                        switch result {
                        case .success(let size):
                            imageCacheSize = UInt64(size)
                        case .failure(let error):
                            Log.error("Failed to calculate Kingfisher cache size: %@", for: .storage, error.localizedDescription)
                            imageCacheSize = 0
                        }
                        
                        let stats = StorageStats(
                            nostrdbSize: nostrdbSize,
                            snapshotSize: snapshotSize,
                            imageCacheSize: imageCacheSize
                        )
                        
                        continuation.resume(returning: stats)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    /// Get the size of the main NostrDB database file
    /// - Returns: Size in bytes, or 0 if file doesn't exist or error occurs
    private func getNostrDBSize() -> UInt64 {
        guard let dbPath = Ndb.db_path else {
            Log.error("Failed to get NostrDB path", for: .storage)
            return 0
        }
        
        let dataFilePath = "\(dbPath)/\(Ndb.main_db_file_name)"
        return getFileSize(at: dataFilePath, description: "NostrDB")
    }
    
    /// Get the size of the snapshot NostrDB database file
    /// - Returns: Size in bytes, or 0 if file doesn't exist or error occurs
    private func getSnapshotDBSize() -> UInt64 {
        guard let snapshotPath = Ndb.snapshot_db_path else {
            Log.error("Failed to get snapshot DB path", for: .storage)
            return 0
        }
        
        let dataFilePath = "\(snapshotPath)/\(Ndb.main_db_file_name)"
        return getFileSize(at: dataFilePath, description: "Snapshot DB")
    }
    
    /// Get the size of a file at the specified path
    /// - Parameters:
    ///   - path: Full path to the file
    ///   - description: Human-readable description for logging
    /// - Returns: Size in bytes, or 0 if file doesn't exist or error occurs
    private func getFileSize(at path: String, description: String) -> UInt64 {
        guard FileManager.default.fileExists(atPath: path) else {
            Log.info("%@ file does not exist at path: %@", for: .storage, description, path)
            return 0
        }
        
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            guard let fileSize = attributes[.size] as? UInt64 else {
                Log.error("Failed to get size attribute for %@", for: .storage, description)
                return 0
            }
            return fileSize
        } catch {
            Log.error("Failed to get file size for %@: %@", for: .storage, description, error.localizedDescription)
            return 0
        }
    }
    
    /// Format bytes into a human-readable string
    /// - Parameter bytes: Number of bytes
    /// - Returns: Formatted string (e.g., "45.3 MB", "1.2 GB")
    static func formatBytes(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useAll]
        formatter.countStyle = .file
        formatter.includesUnit = true
        formatter.isAdaptive = true
        return formatter.string(fromByteCount: Int64(bytes))
    }
}
