//
//  LikeCounter.swift
//  damus
//
//  Created by William Casarin on 2022-04-30.
//

import Foundation


class EventCounter {
    var counts: [String: Int] = [:]
    var user_events: [String: Set<String>] = [:]
    var our_events: [String: NostrEvent] = [:]
    var our_pubkey: String
    
    enum LikeResult {
        case user_already_liked
        case success(Int)
    }
    
    init (our_pubkey: String) {
        self.our_pubkey = our_pubkey
    }
    
    func add_event(_ ev: NostrEvent) -> LikeResult {
        let pubkey = ev.pubkey
        
        if self.user_events[pubkey] == nil {
            self.user_events[pubkey] = Set()
        }
        
        if user_events[pubkey]!.contains(ev.id) {
            // don't double count
            return .user_already_liked
        }
        
        user_events[pubkey]!.insert(ev.id)
        
        if ev.pubkey == self.our_pubkey {
            our_events[ev.id] = ev
        }
        
        if counts[ev.id] == nil {
            counts[ev.id] = 1
            return .success(1)
        }
        
        counts[ev.id]! += 1
        
        return .success(counts[ev.id]!)
    }
}
