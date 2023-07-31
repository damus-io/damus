//
//  LikeCounter.swift
//  damus
//
//  Created by William Casarin on 2022-04-30.
//

import Foundation

enum CountResult {
    case already_counted
    case success(Int)
}

class EventCounter {
    var counts: [NoteId: Int] = [:]
    var user_events: [Pubkey: Set<NoteId>] = [:]
    var our_events: [NoteId: NostrEvent] = [:]
    var our_pubkey: Pubkey

    init(our_pubkey: Pubkey) {
        self.our_pubkey = our_pubkey
    }
    
    func add_event(_ ev: NostrEvent, target: NoteId) -> CountResult {
        let pubkey = ev.pubkey
        
        if self.user_events[pubkey] == nil {
            self.user_events[pubkey] = Set()
        }
        
        if user_events[pubkey]!.contains(target) {
            // don't double count
            return .already_counted
        }
        
        user_events[pubkey]!.insert(target)
        
        if ev.pubkey == self.our_pubkey {
            our_events[target] = ev
        }
        
        if counts[target] == nil {
            counts[target] = 1
            return .success(1)
        }
        
        counts[target]! += 1
        
        return .success(counts[target]!)
    }
}
