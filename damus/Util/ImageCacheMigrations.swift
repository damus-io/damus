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

        let oldCachePath = migration1Done ? migration1KingfisherCachePath() : migration0KingfisherCachePath()

        // New shared cache location
        let newCachePath = kingfisherCachePath().path

        // Check if the old cache exists
        if fileManager.fileExists(atPath: oldCachePath) {
            do {
                // Move the old cache to the new location
                try fileManager.moveItem(atPath: oldCachePath, toPath: newCachePath)
                Log.info("Successfully migrated Kingfisher cache to %s", for: .storage, newCachePath)
            } catch {
                Log.error("Failed to migrate cache: %s", for: .storage, error.localizedDescription)
            }
        }

        // Mark migrations as complete
        defaults.set(true, forKey: migration1Key)
        defaults.set(true, forKey: migration2Key)
    }
    
    static private func migration0KingfisherCachePath() -> String {
        // Implementation note: These are old, so they should not be changed
        // TODO: What if Kingfisher updates these variables?
        let defaultCache = ImageCache.default
        return defaultCache.diskStorage.directoryURL.path
    }
    
    static private func migration1KingfisherCachePath() -> String {
        // Implementation note: These are old, so they are hard-coded on purpose, because we can't change these values from the past.
        let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.damus")!
        return groupURL.appendingPathComponent("ImageCache").path
    }
    
    static func kingfisherCachePath() -> URL {
        let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Constants.DAMUS_APP_GROUP_IDENTIFIER)!
        return groupURL
            .appendingPathComponent("Library")  // TODO: Does Apple provide constants for these? We should NOT be hard-coding these.
            .appendingPathComponent("Caches")
            .appendingPathComponent(Constants.IMAGE_CACHE_DIRNAME)
    }
}
