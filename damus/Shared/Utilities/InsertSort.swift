//
//  InsertSort.swift
//  damus
//
//  Created by William Casarin on 2022-05-09.
//

import Foundation

func insert_uniq_sorted_zap(zaps: inout [Zapping], new_zap: Zapping, cmp: (Zapping, Zapping) -> Bool) -> Bool {
    var i: Int = 0
    
    for zap in zaps {
        if new_zap.request.ev.id == zap.request.ev.id {
            // replace pending
            if !new_zap.is_pending && zap.is_pending {
                print("nwc: replacing pending with real zap \(new_zap.request.ev.id)")
                zaps[i] = new_zap
                return true
            }
            // don't insert duplicate events
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
func insert_uniq_sorted_zap_by_created(zaps: inout [Zapping], new_zap: Zapping) -> Bool {
    return insert_uniq_sorted_zap(zaps: &zaps, new_zap: new_zap) { (a, b) in
        a.created_at > b.created_at
    }
}

@discardableResult
func insert_uniq_sorted_zap_by_amount(zaps: inout [Zapping], new_zap: Zapping) -> Bool {
    return insert_uniq_sorted_zap(zaps: &zaps, new_zap: new_zap) { (a, b) in
        a.amount > b.amount
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
        if new_ev.id_matches(other: event) {
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
