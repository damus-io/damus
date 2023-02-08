//
//  DamusState.swift
//  damus
//
//  Created by William Casarin on 2022-04-30.
//

import Foundation
import LinkPresentation

struct DamusState {
    let pool: RelayPool
    let keypair: Keypair
    let likes: EventCounter
    let boosts: EventCounter
    let contacts: Contacts
    let tips: TipCounter
    let profiles: Profiles
    let dms: DirectMessagesModel
    let previews: PreviewCache
    let zaps: Zaps
    let lnurls: LNUrls
    let settings: UserSettingsStore
    let relay_filters: RelayFilters
    
    var pubkey: String {
        return keypair.pubkey
    }
    
    var is_privkey_user: Bool {
        keypair.privkey != nil
    }

    
    static var empty: DamusState {
        return DamusState.init(pool: RelayPool(), keypair: Keypair(pubkey: "", privkey: ""), likes: EventCounter(our_pubkey: ""), boosts: EventCounter(our_pubkey: ""), contacts: Contacts(our_pubkey: ""), tips: TipCounter(our_pubkey: ""), profiles: Profiles(), dms: DirectMessagesModel(our_pubkey: ""), previews: PreviewCache(), zaps: Zaps(our_pubkey: ""), lnurls: LNUrls(), settings: UserSettingsStore(), relay_filters: RelayFilters(our_pubkey: ""))
    }
}
