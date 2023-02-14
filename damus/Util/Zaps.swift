//
//  Zaps.swift
//  damus
//
//  Created by William Casarin on 2023-01-16.
//

import Foundation

class Zaps {
    var zaps: [String: Zap]
    let our_pubkey: String
    var our_zaps: [String: [Zap]]
    
    var event_counts: [String: Int]
    var event_totals: [String: Int64]
    
    init(our_pubkey: String) {
        self.zaps = [:]
        self.our_pubkey = our_pubkey
        self.our_zaps = [:]
        self.event_counts = [:]
        self.event_totals = [:]
    }
    
    func add_zap(zap: Zap) {
        if zaps[zap.event.id] != nil {
            return
        }
        self.zaps[zap.event.id] = zap
        
        // record our zaps for an event
        if zap.request.ev.pubkey == our_pubkey {
            switch zap.target {
            case .note(let note_target):
                if our_zaps[note_target.note_id] == nil {
                    our_zaps[note_target.note_id] = [zap]
                } else {
                    let _ = insert_uniq_sorted_zap(zaps: &(our_zaps[note_target.note_id]!), new_zap: zap)
                }
            case .profile(_):
                break
            }
        }
        
        // don't count tips to self. lame.
        guard zap.request.ev.pubkey != zap.target.pubkey else {
            return
        }
        
        let id = zap.target.id
        if event_counts[id] == nil {
            event_counts[id] = 0
        }
        
        if event_totals[id] == nil {
            event_totals[id] = 0
        }
        
        event_counts[id] = event_counts[id]! + 1
        event_totals[id] = event_totals[id]! + zap.invoice.amount
        
        notify(.update_stats, zap.target.id)
        
        return
    }
}
