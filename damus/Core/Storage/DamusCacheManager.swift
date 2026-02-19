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

                // Instead of check-then-act (access + removeItem TOCTOU),
                // just attempt removal and let it fail gracefully.
                do {
                    try FileManager.default.removeItem(at: filePath)
                } catch {
                    // File may be in use or already deleted — skip gracefully
                    continue
                }
            }
            
            Log.info("Cache folder cleared successfully.", for: .storage)
            completion?()
        } catch {
            Log.error("Could not clear cache folder", for: .storage)
            completion?()
        }
    }
}
