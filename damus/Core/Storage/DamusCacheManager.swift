//
//  DamusCacheManager.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-10-04.
//

import Foundation
import Kingfisher

struct DamusCacheManager {
    static var shared: DamusCacheManager = DamusCacheManager()
    private static let byteCountFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()
    
    func clear_cache(damus_state: DamusState, completion: (() -> Void)? = nil) {
        Log.info("Clearing all caches", for: .storage)
        clear_kingfisher_cache(completion: {
            clear_cache_folder(completion: {
                Log.info("All caches cleared", for: .storage)
                completion?()
            })
        })
    }
    
    func clear_kingfisher_cache(completion: (() -> Void)? = nil) {
        Log.info("Clearing Kingfisher cache", for: .storage)
        KingfisherManager.shared.cache.calculateDiskStorageSize { result in
            if case .success(let size) = result {
                Log.info("Kingfisher disk cache before clear: %s", for: .storage, self.formattedByteCount(from: UInt64(max(size, 0))))
            }
        }
        KingfisherManager.shared.cache.clearMemoryCache()
        KingfisherManager.shared.cache.clearDiskCache {
            KingfisherManager.shared.cache.calculateDiskStorageSize { result in
                if case .success(let size) = result {
                    Log.info("Kingfisher disk cache after clear: %s", for: .storage, self.formattedByteCount(from: UInt64(max(size, 0))))
                }
            }
            Log.info("Kingfisher cache cleared", for: .storage)
            completion?()
        }
    }
    
    func clear_cache_folder(completion: (() -> Void)? = nil) {
        Log.info("Clearing entire cache folder", for: .storage)
        let cacheURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        
        do {
            let fileNames = try FileManager.default.contentsOfDirectory(atPath: cacheURL.path)
            let fileURLs = fileNames.map { cacheURL.appendingPathComponent($0) }
            let initialSize = totalAllocatedSize(of: fileURLs)
            Log.info("Cache folder contains %d items totaling %s", for: .storage, fileNames.count, formattedByteCount(from: initialSize))
            
            var removedCount = 0
            var freedBytes: UInt64 = 0
            for fileName in fileNames {
                let filePath = cacheURL.appendingPathComponent(fileName)
                
                // Prevent issues by double-checking if files are in use, and do not delete them if they are.
                // This is not perfect. There is still a small chance for a race condition if a file is opened between this check and the file removal.
                errno = 0
                let isBusy = (access(filePath.path, F_OK) == -1 && errno == ETXTBSY)
                if isBusy {
                    Log.debug("Skipping busy cache file: %s", for: .storage, filePath.lastPathComponent)
                    continue
                }
                
                let fileSize = allocatedSize(of: filePath)
                
                try FileManager.default.removeItem(at: filePath)
                removedCount += 1
                freedBytes &+= fileSize
            }
            
            Log.info("Cache folder cleared successfully. Removed %d items freeing %s", for: .storage, removedCount, formattedByteCount(from: freedBytes))
            completion?()
        } catch {
            Log.error("Could not clear cache folder", for: .storage)
        }
    }

    private func formattedByteCount(from bytes: UInt64) -> String {
        let clamped = min(bytes, UInt64(Int64.max))
        return Self.byteCountFormatter.string(fromByteCount: Int64(clamped))
    }
    
    private func allocatedSize(of url: URL) -> UInt64 {
        guard let values = try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]) else {
            return 0
        }
        if let total = values.totalFileAllocatedSize {
            return UInt64(max(total, 0))
        }
        if let single = values.fileAllocatedSize {
            return UInt64(max(single, 0))
        }
        return 0
    }
    
    private func totalAllocatedSize(of urls: [URL]) -> UInt64 {
        return urls.reduce(0) { partialResult, url in
            partialResult &+ allocatedSize(of: url)
        }
    }
}
