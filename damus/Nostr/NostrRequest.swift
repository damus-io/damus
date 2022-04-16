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
}
