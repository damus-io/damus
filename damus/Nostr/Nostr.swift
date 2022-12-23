//
//  Nostr.swift
//  damus
//
//  Created by William Casarin on 2022-04-07.
//

import Foundation


struct Profile: Decodable, Equatable {
    let name: String?
    let display_name: String?
    let about: String?
    let picture: String?
    let website: String?
    let nip05: String?
    let lud06: String?
    let lud16: String?
    
    var lightning_uri: URL? {
        return make_ln_url(self.lud06) ?? make_ln_url(self.lud16)
    }
    
    static func displayName(profile: Profile?, pubkey: String) -> String {
        return profile?.name ?? abbrev_pubkey(pubkey)
    }
}

func make_ln_url(_ str: String?) -> URL? {
    return str.flatMap { URL(string: "lightning:" + $0) }
}

struct NostrSubscription {
    let sub_id: String
    let filter: NostrFilter
}
