//
//  ProfileDatabase.swift
//  damus
//
//  Created by Bryan Montz on 4/30/23.
//

import Foundation
import CoreData

enum ProfileDatabaseError: Error {
    case missing_context
    case outdated_input
}

final class ProfileDatabase {
    
    private let entity_name = "PersistedProfile"
    private var persistent_container: NSPersistentContainer?
    private var background_context: NSManagedObjectContext?
    private let cache_url: URL
    
    init(cache_url: URL = ProfileDatabase.profile_cache_url) {
        self.cache_url = cache_url
        set_up()
    }
    
    private static var profile_cache_url: URL {
        (FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?.appendingPathComponent("profiles"))!
    }
    
    private var persistent_store_description: NSPersistentStoreDescription {
        let description = NSPersistentStoreDescription(url: cache_url)
        description.type = NSSQLiteStoreType
        description.setOption(true as NSNumber, forKey: NSMigratePersistentStoresAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSInferMappingModelAutomaticallyOption)
        description.setOption(true as NSNumber, forKey: NSSQLiteManualVacuumOption)
        return description
    }
    
    private var object_model: NSManagedObjectModel? {
        guard let url = Bundle.main.url(forResource: "Damus", withExtension: "momd") else {
            return nil
        }
        return NSManagedObjectModel(contentsOf: url)
    }
    
    private func set_up() {
        guard let object_model else {
            print("⚠️ Warning: ProfileDatabase failed to load its object model")
            return
        }
        
        persistent_container = NSPersistentContainer(name: "Damus", managedObjectModel: object_model)
        persistent_container?.persistentStoreDescriptions = [persistent_store_description]
        persistent_container?.loadPersistentStores { _, error in
            if let error {
                print("WARNING: ProfileDatabase failed to load: \(error)")
            }
        }
        
        persistent_container?.viewContext.automaticallyMergesChangesFromParent = true
        persistent_container?.viewContext.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
        
        background_context = persistent_container?.newBackgroundContext()
        background_context?.mergePolicy = NSMergePolicy(merge: .mergeByPropertyObjectTrumpMergePolicyType)
    }
    
    private func get_persisted(id: String) -> PersistedProfile? {
        let request = NSFetchRequest<PersistedProfile>(entityName: entity_name)
        request.predicate = NSPredicate(format: "id == %@", id)
        request.fetchLimit = 1
        return try? persistent_container?.viewContext.fetch(request).first
    }
    
    // MARK: - Public
    
    /// Updates or inserts a new Profile into the local database. Rejects profiles whose update date
    /// is older than one we already have. Database writes occur on a background context for best performance.
    /// - Parameters:
    ///   - id: Profile id (pubkey)
    ///   - profile: Profile object to be stored
    ///   - last_update: Date that the Profile was updated
    func upsert(id: String, profile: Profile, last_update: Date) throws {
        guard let context = background_context else {
            throw ProfileDatabaseError.missing_context
        }
        
        var persisted_profile: PersistedProfile?
        if let profile = get_persisted(id: id) {
            if let existing_last_update = profile.last_update, last_update < existing_last_update {
                throw ProfileDatabaseError.outdated_input
            } else {
                persisted_profile = profile
            }
        } else {
            persisted_profile = NSEntityDescription.insertNewObject(forEntityName: entity_name, into: context) as? PersistedProfile
            persisted_profile?.id = id
        }
        persisted_profile?.copyValues(from: profile)
        persisted_profile?.last_update = last_update
        
        try context.save()
    }
    
    func get(id: String) -> Profile? {
        guard let profile = get_persisted(id: id) else {
            return nil
        }
        return Profile(persisted_profile: profile)
    }
}
