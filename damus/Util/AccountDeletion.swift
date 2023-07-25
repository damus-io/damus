//
//  AccountDeletion.swift
//  damus
//
//  Created by William Casarin on 2023-01-30.
//

import Foundation


func created_deleted_account_profile(keypair: FullKeypair) -> NostrEvent? {
    let profile = Profile()
    profile.deleted = true
    profile.about = "account deleted"
    profile.name = "nobody"
    
    guard let content = encode_json(profile) else {
        return nil
    }
    return NostrEvent(content: content, keypair: keypair.to_keypair(), kind: 0)
}
