//
//  DamusState.swift
//  damus
//
//  Created by William Casarin on 2022-04-30.
//

import Foundation

struct DamusState {
    let pool: RelayPool
    let keypair: Keypair
    let likes: EventCounter
    let boosts: EventCounter
    let contacts: Contacts
    let tips: TipCounter
    let image_cache: ImageCache
    let profiles: Profiles
    
    var pubkey: String {
        return keypair.pubkey
    }
    
    static var empty: DamusState {
        return DamusState.init(pool: RelayPool(), keypair: Keypair(pubkey: "", privkey: ""), likes: EventCounter(our_pubkey: ""), boosts: EventCounter(our_pubkey: ""), contacts: Contacts(), tips: TipCounter(our_pubkey: ""), image_cache: ImageCache(), profiles: Profiles())
    }
}
