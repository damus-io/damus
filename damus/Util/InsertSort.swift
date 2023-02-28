//
//  InsertSort.swift
//  damus
//
//  Created by William Casarin on 2022-05-09.
//

import Foundation

func insert_uniq<T: Equatable>(xs: inout [T], new_x: T) -> Bool {
    for x in xs {
        if x == new_x {
            return false
        }
    }
    
    xs.append(new_x)
    return true
}

func insert_uniq_by_pubkey(events: inout [NostrEvent], new_ev: NostrEvent, cmp: (NostrEvent, NostrEvent) -> Bool) -> Bool {
    var i: Int = 0
    
    for event in events {
        // don't insert duplicate events
        if new_ev.pubkey == event.pubkey {
            return false
        }
        
        if cmp(new_ev, event) {
            events.insert(new_ev, at: i)
            return true
        }
        i += 1
    }
    
    events.append(new_ev)
    return true
}

func insert_uniq_sorted_zap(zaps: inout [Zap], new_zap: Zap, cmp: (Zap, Zap) -> Bool) -> Bool {
    var i: Int = 0
    
    for zap in zaps {
        // don't insert duplicate events
        if new_zap.event.id == zap.event.id {
            return false
        }
        
        if cmp(new_zap, zap)  {
            zaps.insert(new_zap, at: i)
            return true
        }
        i += 1
    }
    
    zaps.append(new_zap)
    return true
}

@discardableResult
func insert_uniq_sorted_zap_by_created(zaps: inout [Zap], new_zap: Zap) -> Bool {
    return insert_uniq_sorted_zap(zaps: &zaps, new_zap: new_zap) { (a, b) in
        a.event.created_at > b.event.created_at
    }
}

@discardableResult
func insert_uniq_sorted_zap_by_amount(zaps: inout [Zap], new_zap: Zap) -> Bool {
    return insert_uniq_sorted_zap(zaps: &zaps, new_zap: new_zap) { (a, b) in
        a.invoice.amount > b.invoice.amount
    }
}

func insert_uniq_sorted_event_created(events: inout [NostrEvent], new_ev: NostrEvent) -> Bool {
    return insert_uniq_sorted_event(events: &events, new_ev: new_ev) {
        $0.created_at > $1.created_at
    }
}

@discardableResult
func insert_uniq_sorted_event(events: inout [NostrEvent], new_ev: NostrEvent, cmp: (NostrEvent, NostrEvent) -> Bool) -> Bool {
    var i: Int = 0
    
    for event in events {
        // don't insert duplicate events
        if new_ev.id == event.id {
            return false
        }
        
        if cmp(new_ev, event) {
            events.insert(new_ev, at: i)
            return true
        }
        i += 1
    }
    
    events.append(new_ev)
    return true
}
