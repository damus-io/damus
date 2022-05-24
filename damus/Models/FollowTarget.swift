//
//  FollowNotify.swift
//  damus
//
//  Created by William Casarin on 2022-05-24.
//

import Foundation


enum FollowTarget {
    case pubkey(String)
    case contact(NostrEvent)
    
    var pubkey: String {
        switch self {
        case .pubkey(let pk):
            return pk
        case .contact(let ev):
            return ev.pubkey
        }
    }
}


