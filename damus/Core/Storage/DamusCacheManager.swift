//
//  DamusCacheManager.swift
//  damus
//
//  Created by Daniel D'Aquino on 2023-10-04.
//

import Foundation
import Kingfisher

struct DamusCacheManager {
    static var shared: DamusCacheManager = DamusCacheManager()

    /// Formats byte counts as human-readable strings in MB/GB using file-size style.
    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    /// Clears all application caches sequentially: Kingfisher and cache folder.
    /// Invokes `completion` after all caches are cleared.
    func clear_cache(damus_state: DamusState, completion: (() -> Void)? = nil) {
        Log.info("Clearing all caches", for: .storage)
        clear_kingfisher_cache(completion: {
            clear_cache_folder(completion: {
                Log.info("All caches cleared", for: .storage)
                completion?()
            })
        })
    }

    /// Clears Kingfisher's in-memory and disk image cache.
    /// Logs cache size before and after clearing; invokes `completion` after the disk cache callback completes.
    func clear_kingfisher_cache(completion: (() -> Void)? = nil) {
        Log.info("Clearing Kingfisher cache", for: .storage)
        KingfisherManager.shared.cache.calculateDiskStorageSize { result in
            if case .success(let size) = result {
                Log.info("Kingfisher disk cache before clear: %s", for: .storage, self.formattedByteCount(from: UInt64(max(size, 0))))
            }
            KingfisherManager.shared.cache.clearMemoryCache()
            KingfisherManager.shared.cache.clearDiskCache {
                KingfisherManager.shared.cache.calculateDiskStorageSize { result in
                    if case .success(let size) = result {
                        Log.info("Kingfisher disk cache after clear: %s", for: .storage, self.formattedByteCount(from: UInt64(max(size, 0))))
                    }
                    Log.info("Kingfisher cache cleared", for: .storage)
                    completion?()
                }
            }
        }
    }

    /// Clears the application's Caches directory by removing all files and subdirectories.
    func clear_cache_folder(completion: (() -> Void)? = nil) {
        Log.info("Clearing entire cache folder", for: .storage)
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]

        do {
            let fileNames = try FileManager.default.contentsOfDirectory(atPath: cacheURL.path)

            for fileName in fileNames {
                let filePath = cacheURL.appendingPathComponent(fileName)

                // Prevent issues by double-checking if files are in use, and do not delete them if they are.
                // This is not perfect. There is still a small chance for a race condition if a file is opened between this check and the file removal.
                let isBusy = (!(access(filePath.path, F_OK) == -1 && errno == ETXTBSY))
                if isBusy {
                    continue
                }

                try FileManager.default.removeItem(at: filePath)
            }

            Log.info("Cache folder cleared successfully.", for: .storage)
            completion?()
        } catch {
            Log.error("Could not clear cache folder", for: .storage)
            completion?()
        }
    }

    /// Formats a byte count as a human-readable string (e.g., "1.5 GB").
    private func formattedByteCount(from bytes: UInt64) -> String {
        let clamped = min(bytes, UInt64(Int64.max))
        return Self.byteCountFormatter.string(fromByteCount: Int64(clamped))
    }
}
