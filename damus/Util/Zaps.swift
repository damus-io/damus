//
//  Zaps.swift
//  damus
//
//  Created by William Casarin on 2023-01-16.
//

import Foundation

class Zaps {
    private(set) var zaps: [String: Zapping]
    let our_pubkey: String
    var our_zaps: [String: [Zapping]]
    
    private(set) var event_counts: [String: Int]
    private(set) var event_totals: [String: Int64]
    
    init(our_pubkey: String) {
        self.zaps = [:]
        self.our_pubkey = our_pubkey
        self.our_zaps = [:]
        self.event_counts = [:]
        self.event_totals = [:]
    }
    
    func remove_zap(reqid: String) -> Zapping? {
        var res: Zapping? = nil
        for kv in our_zaps {
            let ours = kv.value
            guard let zap = ours.first(where: { z in z.request.ev.id == reqid }) else {
                continue
            }
            
            res = zap
            
            our_zaps[kv.key] = ours.filter { z in z.request.ev.id != reqid }
            
            if let count = event_counts[zap.target.id] {
                event_counts[zap.target.id] = count - 1
            }
            if let total = event_totals[zap.target.id] {
                event_totals[zap.target.id] = total - zap.amount
            }
            
            // we found the request id, we can stop looking
            break
        }
        
        self.zaps.removeValue(forKey: reqid)
        return res
    }
    
    func add_zap(zap: Zapping) {
        if zaps[zap.request.ev.id] != nil {
            return
        }
        self.zaps[zap.request.ev.id] = zap
        if let zap_id = zap.event?.id {
            self.zaps[zap_id] = zap
        }
        
        // record our zaps for an event
        if zap.request.ev.pubkey == our_pubkey {
            switch zap.target {
            case .note(let note_target):
                if our_zaps[note_target.note_id] == nil {
                    our_zaps[note_target.note_id] = [zap]
                } else {
                    insert_uniq_sorted_zap_by_amount(zaps: &(our_zaps[note_target.note_id]!), new_zap: zap)
                }
            case .profile:
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
        event_totals[id] = event_totals[id]! + zap.amount
        
        notify(.update_stats, zap.target.id)
    }
}

func remove_zap(reqid: ZapRequestId, zapcache: Zaps, evcache: EventCache) {
    guard let zap = zapcache.remove_zap(reqid: reqid.reqid) else {
        return
    }
    evcache.get_cache_data(zap.target.id).zaps_model.remove(reqid: reqid.reqid)
}
