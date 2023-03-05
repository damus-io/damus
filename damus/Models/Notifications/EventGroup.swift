//
//  ReactionGroup.swift
//  damus
//
//  Created by William Casarin on 2023-02-21.
//

import Foundation

class EventGroup {
    var events: [NostrEvent]
    
    var last_event_at: Int64 {
        guard let first = self.events.first else {
            return 0
        }
        
        return first.created_at
    }
    
    init() {
        self.events = []
    }
    
    init(events: [NostrEvent]) {
        self.events = events
    }
    
    func insert(_ ev: NostrEvent) -> Bool {
        return insert_uniq_sorted_event_created(events: &events, new_ev: ev)
    }
}
