//
//  Profiles.swift
//  damus
//
//  Created by William Casarin on 2022-04-17.
//

import Foundation

class Profiles {
    
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
}
