//
//  ProfileUpdate.swift
//  damus
//
//  Created by William Casarin on 2022-05-06.
//

import Foundation


enum ProfileUpdate {
    case manual(pubkey: Pubkey, profile: Profile)
    case remote(pubkey: Pubkey)

    var pubkey: Pubkey {
        switch self {
        case .manual(let pubkey, _):
            return pubkey
        case .remote(let pubkey):
            return pubkey
        }
    }
}
