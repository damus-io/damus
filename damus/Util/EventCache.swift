//
//  EventCache.swift
//  damus
//
//  Created by William Casarin on 2023-02-21.
//

import Foundation

class EventCache {
    private var events: [String: NostrEvent]
    
    func lookup(_ evid: String) -> NostrEvent? {
        return events[evid]
    }
    
    func insert(_ ev: NostrEvent) {
        guard events[ev.id] == nil else {
            return
        }
        events[ev.id] = ev
    }
    
    init() {
        self.events = [:]
    }
}
