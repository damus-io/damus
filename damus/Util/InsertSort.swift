//
//  InsertSort.swift
//  damus
//
//  Created by William Casarin on 2022-05-09.
//

import Foundation


func insert_uniq_sorted_event(events: inout [NostrEvent], new_ev: NostrEvent) -> Bool {
    var i: Int = 0
    
    for event in events {
        // don't insert duplicate events
        if new_ev.id == event.id {
            return false
        }
        
        if new_ev.created_at < event.created_at {
            events.insert(new_ev, at: i)
            return true
        }
        i += 1
    }
    
    events.append(new_ev)
    return true
}
