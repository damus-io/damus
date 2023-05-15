//
//  Profiles.swift
//  damus
//
//  Created by William Casarin on 2022-04-17.
//

import Foundation

class Profiles {
    
    static let db_freshness_threshold: TimeInterval = 24 * 60 * 60
    
    /// This queue is used to synchronize access to the profiles dictionary, which
    /// prevents data races from crashing the app.
    private var queue = DispatchQueue(label: "io.damus.profiles",
                                      qos: .userInteractive,
                                      attributes: .concurrent)
    
    var profiles: [String: TimestampedProfile] = [:]
    var validated: [String: NIP05] = [:]
    var nip05_pubkey: [String: String] = [:]
    var zappers: [String: String] = [:]
    
    private let database = ProfileDatabase()
    
    func is_validated(_ pk: String) -> NIP05? {
        validated[pk]
    }
    
    func lookup_zapper(pubkey: String) -> String? {
        zappers[pubkey]
    }
    
    func add(id: String, profile: TimestampedProfile) {
        queue.async(flags: .barrier) {
            self.profiles[id] = profile
        }
        
        do {
            try database.upsert(id: id, profile: profile.profile, last_update: Date(timeIntervalSince1970: TimeInterval(profile.timestamp)))
        } catch {
            print("⚠️ Warning: Profiles failed to save a profile: \(error)")
        }
    }
    
    func lookup(id: String) -> Profile? {
        var profile: Profile?
        queue.sync {
            profile = profiles[id]?.profile
        }
        return profile ?? database.get(id: id)
    }
    
    func lookup_with_timestamp(id: String) -> TimestampedProfile? {
        queue.sync {
            return profiles[id]
        }
    }
    
    func has_fresh_profile(id: String) -> Bool {
        // check memory first
        var profile: Profile?
        queue.sync {
            profile = profiles[id]?.profile
        }
        if profile != nil {
            return true
        }
        
        // then disk
        guard let persisted_profile = database.get_persisted(id: id),
              let pull_date = persisted_profile.network_pull_date else {
            return false
        }
        return Date.now.timeIntervalSince(pull_date) < Profiles.db_freshness_threshold
    }
}
