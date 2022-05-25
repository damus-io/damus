//
//  Nostr.swift
//  damus
//
//  Created by William Casarin on 2022-04-07.
//

import Foundation


struct Profile: Decodable {
    let name: String?
    let display_name: String?
    let about: String?
    let picture: String?
    
    static func displayName(profile: Profile?, pubkey: String) -> String {
        return profile?.name ?? abbrev_pubkey(pubkey)
    }
}

enum NostrTag {
    case other_event(OtherEvent)
    case key_event(KeyEvent)
}

struct NostrSubscription {
    let sub_id: String
    let filter: NostrFilter
}



