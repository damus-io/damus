//
//  Profiles.swift
//  damus
//
//  Created by William Casarin on 2022-04-17.
//

import Foundation

class ValidationModel: ObservableObject {
    @Published var validated: NIP05?

    init() {
        self.validated = nil
    }
}

class ProfileDataModel: ObservableObject {
    @Published var profile: TimestampedProfile?

    init() {
        self.profile = nil
    }
}

class ProfileData {
    var status: UserStatusModel
    var profile_model: ProfileDataModel
    var validation_model: ValidationModel
    var zapper: Pubkey?

    init() {
        status = .init()
        profile_model = .init()
        validation_model = .init()
        zapper = nil
    }
}

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
    
    private var profiles: [Pubkey: ProfileData] = [:]

    var nip05_pubkey: [String: Pubkey] = [:]

    private let database = ProfileDatabase()

    let user_search_cache: UserSearchCache

    init(user_search_cache: UserSearchCache) {
        self.user_search_cache = user_search_cache
    }
    
    func is_validated(_ pk: Pubkey) -> NIP05? {
        validated_queue.sync {
            self.profile_data(pk).validation_model.validated
        }
    }

    func invalidate_nip05(_ pk: Pubkey) {
        validated_queue.async(flags: .barrier) {
            self.profile_data(pk).validation_model.validated = nil
        }
    }

    func set_validated(_ pk: Pubkey, nip05: NIP05?) {
        validated_queue.async(flags: .barrier) {
            self.profile_data(pk).validation_model.validated = nip05
        }
    }
    
    func profile_data(_ pubkey: Pubkey) -> ProfileData {
        guard let data = profiles[pubkey] else {
            let data = ProfileData()
            profiles[pubkey] = data
            return data
        }

        return data
    }

    func lookup_zapper(pubkey: Pubkey) -> Pubkey? {
        profile_data(pubkey).zapper
    }
    
    func add(id: Pubkey, profile: TimestampedProfile) {
        profiles_queue.async(flags: .barrier) {
            let old_timestamped_profile = self.profile_data(id).profile_model.profile
            self.profile_data(id).profile_model.profile = profile
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
    
    func lookup(id: Pubkey) -> Profile? {
        var profile: Profile?
        profiles_queue.sync {
            profile = self.profile_data(id).profile_model.profile?.profile
        }
        return profile ?? database.get(id: id)
    }
    
    func lookup_with_timestamp(id: Pubkey) -> TimestampedProfile? {
        profiles_queue.sync {
            return self.profile_data(id).profile_model.profile
        }
    }
    
    func has_fresh_profile(id: Pubkey) -> Bool {
        var profile: Profile?
        profiles_queue.sync {
            profile = self.profile_data(id).profile_model.profile?.profile
        }
        if profile != nil {
            return true
        }
        // check memory first
        return false

        // then disk
        guard let pull_date = database.get_network_pull_date(id: id) else {
            return false
        }
        return Date.now.timeIntervalSince(pull_date) < Profiles.db_freshness_threshold
    }
}


func invalidate_zapper_cache(pubkey: Pubkey, profiles: Profiles, lnurl: LNUrls) {
    profiles.profile_data(pubkey).zapper = nil
    lnurl.endpoints.removeValue(forKey: pubkey)
}
