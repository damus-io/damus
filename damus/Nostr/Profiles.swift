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
    private var profiles_queue = DispatchQueue(label: "io.damus.profiles",
                                      qos: .userInteractive,
                                      attributes: .concurrent)

    private var validated_queue = DispatchQueue(label: "io.damus.profiles.validated",
                                                  qos: .userInteractive,
                                                  attributes: .concurrent)
    
    private var profiles: [String: TimestampedProfile] = [:]
    private var validated: [String: NIP05] = [:]
    var nip05_pubkey: [String: String] = [:]
    var zappers: [String: String] = [:]
    
    private let database = ProfileDatabase()

    let user_search_cache: UserSearchCache

    init(user_search_cache: UserSearchCache) {
        self.user_search_cache = user_search_cache
    }
    
    func is_validated(_ pk: String) -> NIP05? {
        validated_queue.sync {
            validated[pk]
        }
    }

    func invalidate_nip05(_ pk: String) {
        validated_queue.async(flags: .barrier) {
            self.validated.removeValue(forKey: pk)
        }
    }

    func set_validated(_ pk: String, nip05: NIP05?) {
        validated_queue.async(flags: .barrier) {
            self.validated[pk] = nip05
        }
    }
    
    func enumerated() -> EnumeratedSequence<[String: TimestampedProfile]> {
        return profiles_queue.sync {
            return profiles.enumerated()
        }
    }
    
    func lookup_zapper(pubkey: String) -> String? {
        zappers[pubkey]
    }
    
    func add(id: String, profile: TimestampedProfile) {
        profiles_queue.async(flags: .barrier) {
            let old_timestamped_profile = self.profiles[id]
            self.profiles[id] = profile
            self.user_search_cache.updateProfile(id: id, profiles: self, oldProfile: old_timestamped_profile?.profile, newProfile: profile.profile)
        }
        
        Task {
            do {
                try await database.upsert(id: id, profile: profile.profile, last_update: Date(timeIntervalSince1970: TimeInterval(profile.timestamp)))
            } catch {
                print("⚠️ Warning: Profiles failed to save a profile: \(error)")
            }
        }
    }
    
    func lookup(id: String) -> Profile? {
        var profile: Profile?
        profiles_queue.sync {
            profile = profiles[id]?.profile
        }
        return profile ?? database.get(id: id)
    }
    
    func lookup_with_timestamp(id: String) -> TimestampedProfile? {
        profiles_queue.sync {
            return profiles[id]
        }
    }
    
    func has_fresh_profile(id: String) -> Bool {
        // check memory first
        var profile: Profile?
        profiles_queue.sync {
            profile = profiles[id]?.profile
        }
        if profile != nil {
            return true
        }
        
        // then disk
        guard let pull_date = database.get_network_pull_date(id: id) else {
            return false
        }
        return Date.now.timeIntervalSince(pull_date) < Profiles.db_freshness_threshold
    }
}


func invalidate_zapper_cache(pubkey: String, profiles: Profiles, lnurl: LNUrls) {
    profiles.zappers.removeValue(forKey: pubkey)
    lnurl.endpoints.removeValue(forKey: pubkey)
}
