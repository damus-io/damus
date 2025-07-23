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
        KingfisherManager.shared.cache.clearMemoryCache()
        KingfisherManager.shared.cache.clearDiskCache {
            Log.info("Kingfisher cache cleared", for: .storage)
            completion?()
        }
    }
    
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
        }
    }
}
