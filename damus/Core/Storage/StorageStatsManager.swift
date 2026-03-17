//
//  StorageStatsManager.swift
//  damus
//
//  Created by Daniel D’Aquino on 2026-02-20.
//

import Foundation
import Kingfisher

/// Storage statistics for various Damus data stores
struct StorageStats: Hashable {
    /// Detailed breakdown of NostrDB storage by kind, indices, and other
    let nostrdbDetails: NdbStats?

    /// Size of the main NostrDB database file in bytes (total)
    let nostrdbSize: UInt64

    /// Size of the snapshot NostrDB database file in bytes
    let snapshotSize: UInt64

    /// Size of the Kingfisher image cache in bytes
    let imageCacheSize: UInt64

    /// Size of the video cache in bytes (`~/Library/Caches/video_cache/`)
    let videoCacheSize: UInt64

    /// Size of all other storage not covered by the tracked categories
    let otherSize: UInt64

    /// Total storage used across all data stores
    var totalSize: UInt64 {
        return nostrdbSize + snapshotSize + imageCacheSize + videoCacheSize + otherSize
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
    /// - Detailed NostrDB breakdown (if ndb instance provided)
    /// - Snapshot database file size
    /// - Kingfisher image cache size
    ///
    /// - Parameter ndb: Optional Ndb instance to get detailed storage breakdown
    /// - Returns: StorageStats containing all calculated sizes
    /// - Throws: Error if critical file operations fail
    func calculateStorageStats(ndb: Ndb? = nil) async throws -> StorageStats {
        // Run all file operations on background thread
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let nostrdbSize = self.getNostrDBSize()
                    let snapshotSize = self.getSnapshotDBSize()
                    
                    // Get detailed NostrDB stats if ndb instance provided
                    let nostrdbDetails: NdbStats? = ndb?.getStats(physicalSize: nostrdbSize)
                    
                    // Calculate total container size from file enumeration
                    let containerTotal = self.containerTotalSize()
                    let videoCacheSize = self.getVideoCacheSize()

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

                        let trackedSize = nostrdbSize + snapshotSize + imageCacheSize + videoCacheSize
                        let otherSize: UInt64 = containerTotal > trackedSize ? containerTotal - trackedSize : 0

                        let stats = StorageStats(
                            nostrdbDetails: nostrdbDetails,
                            nostrdbSize: nostrdbSize,
                            snapshotSize: snapshotSize,
                            imageCacheSize: imageCacheSize,
                            videoCacheSize: videoCacheSize,
                            otherSize: otherSize
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
    
    /// Get the total size of the video cache directory
    /// - Returns: Size in bytes, or 0 if directory doesn't exist or error occurs
    private func getVideoCacheSize() -> UInt64 {
        guard let cachesURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return 0
        }
        let videoCacheURL = cachesURL.appendingPathComponent("video_cache")
        return getDirectorySize(at: videoCacheURL, description: "Video Cache")
    }

    /// Get the total size of all files in a directory (recursively)
    /// - Parameters:
    ///   - url: URL of the directory
    ///   - description: Human-readable description for logging
    /// - Returns: Size in bytes, or 0 if directory doesn't exist or error occurs
    private func getDirectorySize(at url: URL, description: String) -> UInt64 {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return 0 }

        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var total: UInt64 = 0
        for case let fileURL as URL in enumerator {
            guard let rv = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  rv.isRegularFile == true,
                  let size = rv.fileSize else { continue }
            total += UInt64(max(0, size))
        }
        return total
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
    
    /// Sum the size of all files across the app sandbox and shared app group container.
    ///
    /// Unlike `containerFileBreakdown()`, this enumerates files without collecting
    /// them into an intermediate array, avoiding allocation proportional to file count.
    ///
    /// - Returns: Total size in bytes.
    func containerTotalSize() -> UInt64 {
        let fm = FileManager.default
        var roots: [URL] = []

        if let home = fm.urls(for: .documentDirectory, in: .userDomainMask).first?.deletingLastPathComponent() {
            roots.append(home)
        }
        if let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.damus") {
            roots.append(groupURL)
        }

        var total: UInt64 = 0
        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let fileURL as URL in enumerator {
                guard let rv = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      rv.isRegularFile == true,
                      let size = rv.fileSize else { continue }
                total += UInt64(max(0, size))
            }
        }
        return total
    }

    /// A single file entry produced by container enumeration
    struct ContainerFileEntry {
        /// Human-readable label for the container root (e.g. "Documents")
        let containerLabel: String
        /// File path relative to the container root URL
        let relativePath: String
        /// File size in bytes
        let size: UInt64
    }
    
    /// Enumerate every file in the app sandbox and the shared app group container.
    ///
    /// Results are sorted by size descending so the largest files appear first,
    /// making it easy to spot unexpectedly large or orphaned items.
    ///
    /// - Returns: Array of `ContainerFileEntry` values, one per regular file found.
    func containerFileBreakdown() -> [ContainerFileEntry] {
        let fm = FileManager.default
        
        // Collect (label, root URL) pairs to walk
        var roots: [(label: String, url: URL)] = []
        
        // Primary sandbox container
        if let home = fm.urls(for: .documentDirectory, in: .userDomainMask).first?.deletingLastPathComponent() {
            roots.append((label: "Sandbox", url: home))
        }
        
        // Shared app group container (legacy nostrdb + snapshot)
        if let groupURL = fm.containerURL(forSecurityApplicationGroupIdentifier: "group.com.damus") {
            roots.append((label: "AppGroup", url: groupURL))
        }
        
        var entries: [ContainerFileEntry] = []
        
        for root in roots {
            guard let enumerator = fm.enumerator(
                at: root.url,
                includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }
            
            for case let fileURL as URL in enumerator {
                guard let resourceValues = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      resourceValues.isRegularFile == true,
                      let size = resourceValues.fileSize else { continue }
                
                // Build a path relative to the container root
                let relativePath: String
                if fileURL.path.hasPrefix(root.url.path) {
                    relativePath = String(fileURL.path.dropFirst(root.url.path.count))
                        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                } else {
                    relativePath = fileURL.path
                }
                
                entries.append(ContainerFileEntry(
                    containerLabel: root.label,
                    relativePath: relativePath,
                    size: UInt64(max(0, size))
                ))
            }
        }
        
        // Largest files first
        entries.sort { $0.size > $1.size }
        return entries
    }
}
