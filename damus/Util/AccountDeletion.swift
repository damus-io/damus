//
//  AccountDeletion.swift
//  damus
//
//  Created by William Casarin on 2023-01-30.
//

import Foundation


func created_deleted_account_profile(keypair: FullKeypair) -> NostrEvent {
    var profile = Profile()
    profile.deleted = true
    profile.about = "account deleted"
    profile.name = "nobody"
    
    let content = encode_json(profile)!
    let ev = NostrEvent(content: content, pubkey: keypair.pubkey, kind: 0)
    ev.id = calculate_event_id(ev: ev)
    ev.sig = sign_event(privkey: keypair.privkey, ev: ev)
    return ev
}
