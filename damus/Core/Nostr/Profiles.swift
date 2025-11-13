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

class ProfileData {
    var status: UserStatusModel
    var validation_model: ValidationModel
    var zapper: Pubkey?

    init() {
        status = .init()
        validation_model = .init()
        zapper = nil
    }
}

class Profiles {
    private var ndb: Ndb

    static let db_freshness_threshold: TimeInterval = 24 * 60 * 8

    @MainActor
    private var profiles: [Pubkey: ProfileData] = [:]

    // Map of validated NIP-05 address to pubkey.
    @MainActor
    var nip05_pubkey: [String: Pubkey] = [:]

    init(ndb: Ndb) {
        self.ndb = ndb
    }

    @MainActor
    func is_validated(_ pk: Pubkey) -> NIP05? {
        self.profile_data(pk).validation_model.validated
    }

    @MainActor
    func invalidate_nip05(_ pk: Pubkey) {
        self.profile_data(pk).validation_model.validated = nil
    }

    @MainActor
    func set_validated(_ pk: Pubkey, nip05: NIP05?) {
        self.profile_data(pk).validation_model.validated = nip05
    }

    @MainActor
    func profile_data(_ pubkey: Pubkey) -> ProfileData {
        guard let data = profiles[pubkey] else {
            let data = ProfileData()
            profiles[pubkey] = data
            return data
        }

        return data
    }

    @MainActor
    func lookup_zapper(pubkey: Pubkey) -> Pubkey? {
        profile_data(pubkey).zapper
    }

    func lookup_with_timestamp<T>(_ pubkey: Pubkey, borrow lendingFunction: (_: borrowing ProfileRecord?) throws -> T) throws -> T {
        return try ndb.lookup_profile(pubkey, borrow: lendingFunction)
    }
    
    func lookup_lnurl(_ pubkey: Pubkey) throws -> String? {
        return try lookup_with_timestamp(pubkey, borrow: { pr in
            switch pr {
            case .some(let pr): return pr.lnurl
            case .none: return nil
            }
        })
    }

    func lookup_by_key<T>(key: ProfileKey, borrow lendingFunction: (_: borrowing ProfileRecord?) throws -> T) throws -> T {
        return try ndb.lookup_profile_by_key(key: key, borrow: lendingFunction)
    }

    func search(_ query: String, limit: Int) throws -> [Pubkey] {
        try ndb.search_profile(query, limit: limit)
    }

    func lookup(id: Pubkey) throws -> Profile? {
        return try ndb.lookup_profile(id, borrow: { pr in
            switch pr {
            case .none:
                return nil
            case .some(let profileRecord):
                // This will clone the value to make it owned and safe to return.
                return profileRecord.profile
            }
        })
    }

    func lookup_key_by_pubkey(_ pubkey: Pubkey) throws -> ProfileKey? {
        try ndb.lookup_profile_key(pubkey)
    }

    func has_fresh_profile(id: Pubkey) throws -> Bool {
        guard let fetched_at = try ndb.read_profile_last_fetched(pubkey: id)
        else {
            return false
        }
        
        // In situations where a batch of profiles was fetched all at once,
        // this will reduce the herding of the profile requests
        let fuzz = Double.random(in: -60...60)
        let threshold = Profiles.db_freshness_threshold + fuzz
        let fetch_date = Date(timeIntervalSince1970: Double(fetched_at))
        
        let since = Date.now.timeIntervalSince(fetch_date)
        let fresh = since < threshold

        //print("fresh = \(fresh): fetch_date \(since) < threshold \(threshold) \(id)")

        return fresh
    }
}


@MainActor
func invalidate_zapper_cache(pubkey: Pubkey, profiles: Profiles, lnurl: LNUrls) {
    profiles.profile_data(pubkey).zapper = nil
    lnurl.endpoints.removeValue(forKey: pubkey)
}
