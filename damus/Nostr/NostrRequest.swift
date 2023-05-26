//
//  NostrRequest.swift
//  damus
//
//  Created by William Casarin on 2022-04-12.
//

import Foundation

struct NostrSubscribe {
    let filters: [NostrFilter]
    let sub_id: String
}

enum NostrRequest {
    case subscribe(NostrSubscribe)
    case unsubscribe(String)
    case event(NostrEvent)
    
    var is_write: Bool {
        switch self {
        case .subscribe:
            return false
        case .unsubscribe:
            return false
        case .event:
            return true
        }
    }
    
    var is_read: Bool {
        return !is_write
    }
}
