//
//  FollowNotify.swift
//  damus
//
//  Created by William Casarin on 2022-05-24.
//

import Foundation

enum FollowTarget {
    case pubkey(Pubkey)
    case contact(NostrEvent)

    var follow_ref: FollowRef {
        FollowRef.pubkey(pubkey)
    }

    var pubkey: Pubkey {
        switch self {
        case .pubkey(let pk):   return pk
        case .contact(let ev):  return ev.pubkey
        }
    }
}


