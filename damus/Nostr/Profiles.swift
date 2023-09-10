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

    static let db_freshness_threshold: TimeInterval = 24 * 60 * 60

    @MainActor
    private var profiles: [Pubkey: ProfileData] = [:]

    @MainActor
    var nip05_pubkey: [String: Pubkey] = [:]

    let user_search_cache: UserSearchCache

    init(user_search_cache: UserSearchCache, ndb: Ndb) {
        self.user_search_cache = user_search_cache
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

    func lookup_with_timestamp(_ pubkey: Pubkey) -> NdbTxn<ProfileRecord?> {
        return ndb.lookup_profile(pubkey)
    }

    func lookup_by_key(key: ProfileKey) -> NdbTxn<ProfileRecord?> {
        return ndb.lookup_profile_by_key(key: key)
    }

    func lookup(id: Pubkey) -> NdbTxn<Profile?> {
        return ndb.lookup_profile(id).map({ pr in pr?.profile })
    }

    func lookup_key_by_pubkey(_ pubkey: Pubkey) -> ProfileKey? {
        return ndb.lookup_profile_key(pubkey)
    }

    func has_fresh_profile(id: Pubkey) -> Bool {
        guard let recv = lookup_with_timestamp(id).unsafeUnownedValue?.receivedAt else { return false }
        return Date.now.timeIntervalSince(Date(timeIntervalSince1970: Double(recv))) < Profiles.db_freshness_threshold
    }
}


@MainActor
func invalidate_zapper_cache(pubkey: Pubkey, profiles: Profiles, lnurl: LNUrls) {
    profiles.profile_data(pubkey).zapper = nil
    lnurl.endpoints.removeValue(forKey: pubkey)
}
