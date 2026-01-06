//
//  ImageCacheMigrations.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-04-26.
//

import Foundation
import Kingfisher

struct ImageCacheMigrations {
    static func migrateKingfisherCacheIfNeeded() {
        let fileManager = FileManager.default
        let defaults = UserDefaults.standard
        let migration1Key = "KingfisherCacheMigrated"   // Never ever changes
        let migration2Key = "KingfisherCacheMigratedV2" // Never ever changes
        
        let migration1Done = defaults.bool(forKey: migration1Key)
        let migration2Done = defaults.bool(forKey: migration2Key)

        guard !migration1Done || !migration2Done else {
            // All migrations are already done. Skip.
            return
        }

        // In test environments, app group may not be available - skip migration
        let oldCachePath: String
        if migration1Done {
            guard let path = migration1KingfisherCachePath() else {
                // App group unavailable (e.g., test environment) - mark as done and skip
                defaults.set(true, forKey: migration1Key)
                defaults.set(true, forKey: migration2Key)
                return
            }
            oldCachePath = path
        } else {
            oldCachePath = migration0KingfisherCachePath()
        }

        // New shared cache location
        let newCachePath = kingfisherCachePath().path

        if fileManager.fileExists(atPath: oldCachePath) {
            do {
                // Move the old cache to the new location
                try fileManager.moveItem(atPath: oldCachePath, toPath: newCachePath)
                Log.info("Successfully migrated Kingfisher cache to %s", for: .storage, newCachePath)
            } catch {
                do {
                    // Cache data is not essential, fallback to deleting the cache and starting all over
                    // It's better than leaving significant garbage data stuck indefinitely on the user's phone
                    try fileManager.removeItem(atPath: newCachePath)
                    try fileManager.removeItem(atPath: oldCachePath)
                }
                catch {
                    Log.error("Failed to migrate cache: %s", for: .storage, error.localizedDescription)
                    return  // Do not mark them as complete, we can try again next time the user reloads the app
                }
            }
        }
        
        // Mark migrations as complete
        defaults.set(true, forKey: migration1Key)
        defaults.set(true, forKey: migration2Key)
    }
    
    static private func migration0KingfisherCachePath() -> String {
        // Implementation note: These are old, so they should not be changed
        let defaultCache = ImageCache.default
        return defaultCache.diskStorage.directoryURL.path
    }
    
    static private func migration1KingfisherCachePath() -> String? {
        // Implementation note: These are old, so they are hard-coded on purpose, because we can't change these values from the past.
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.damus") else {
            return nil
        }
        return groupURL.appendingPathComponent("ImageCache").path
    }
    
    /// The latest path for kingfisher to store cached images on.
    ///
    /// Documentation references:
    /// - https://developer.apple.com/documentation/foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:)#:~:text=The%20system%20creates%20only%20the%20Library/Caches%20subdirectory%20automatically
    /// - https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html#:~:text=Put%20data%20cache,files%20as%20needed.
    static func kingfisherCachePath() -> URL {
        // Fall back to temporary directory in test environments where app group is unavailable
        guard let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Constants.DAMUS_APP_GROUP_IDENTIFIER) else {
            return FileManager.default.temporaryDirectory
                .appendingPathComponent("Caches")
                .appendingPathComponent(Constants.IMAGE_CACHE_DIRNAME)
        }
        return groupURL
            .appendingPathComponent("Library")
            .appendingPathComponent("Caches")
            .appendingPathComponent(Constants.IMAGE_CACHE_DIRNAME)
    }
}
