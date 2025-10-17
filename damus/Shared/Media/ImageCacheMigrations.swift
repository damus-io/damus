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
        
        guard fileManager.containerURL(forSecurityApplicationGroupIdentifier: Constants.DAMUS_APP_GROUP_IDENTIFIER) != nil else {
            Log.error("Skipping Kingfisher cache migration because app group container is unavailable", for: .storage)
            return
        }
        
        let defaults = UserDefaults.standard
        let migration1Key = "KingfisherCacheMigrated"   // Never ever changes
        let migration2Key = "KingfisherCacheMigratedV2" // Never ever changes
        
        let migration1Done = defaults.bool(forKey: migration1Key)
        let migration2Done = defaults.bool(forKey: migration2Key)

        guard !migration1Done || !migration2Done else {
            // All migrations are already done. Skip.
            return
        }

        let oldCachePath = migration1Done ? migration1KingfisherCachePath() : migration0KingfisherCachePath()

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
    
    static private func migration1KingfisherCachePath() -> String {
        // Implementation note: These are old, so they are hard-coded on purpose, because we can't change these values from the past.
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.damus") {
            return groupURL.appendingPathComponent("ImageCache").path
        }
        
        let fallback = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Constants.IMAGE_CACHE_DIRNAME)
            .path
        Log.error("Legacy Kingfisher cache path unavailable; using fallback at %s", for: .storage, fallback)
        return fallback
    }
    
    /// The latest path for kingfisher to store cached images on.
    ///
    /// Documentation references:
    /// - https://developer.apple.com/documentation/foundation/filemanager/containerurl(forsecurityapplicationgroupidentifier:)#:~:text=The%20system%20creates%20only%20the%20Library/Caches%20subdirectory%20automatically
    /// - https://developer.apple.com/library/archive/documentation/FileManagement/Conceptual/FileSystemProgrammingGuide/FileSystemOverview/FileSystemOverview.html#:~:text=Put%20data%20cache,files%20as%20needed.
    static func kingfisherCachePath() -> URL {
        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Constants.DAMUS_APP_GROUP_IDENTIFIER) {
            return groupURL
                .appendingPathComponent("Library")
                .appendingPathComponent("Caches")
                .appendingPathComponent(Constants.IMAGE_CACHE_DIRNAME)
        }
        
        let fallbackURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(Constants.IMAGE_CACHE_DIRNAME)
        Log.error("App group container unavailable; using fallback cache directory at %s", for: .storage, fallbackURL.path)
        return fallbackURL
    }
}
