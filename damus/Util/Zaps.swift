//
//  Zaps.swift
//  damus
//
//  Created by William Casarin on 2023-01-16.
//

import Foundation

class Zaps {
    private(set) var zaps: [NoteId: Zapping]
    let our_pubkey: Pubkey
    var our_zaps: [NoteId: [Zapping]]

    private(set) var event_counts: [NoteId: Int]
    private(set) var event_totals: [NoteId: Int64]

    init(our_pubkey: Pubkey) {
        self.zaps = [:]
        self.our_pubkey = our_pubkey
        self.our_zaps = [:]
        self.event_counts = [:]
        self.event_totals = [:]
    }
    
    func remove_zap(reqid: NoteId) -> Zapping? {
        var res: Zapping? = nil
        for kv in our_zaps {
            let ours = kv.value
            guard let zap = ours.first(where: { z in z.request.ev.id == reqid }) else {
                continue
            }
            
            res = zap
            
            our_zaps[kv.key] = ours.filter { z in z.request.ev.id != reqid }

            // counts for note zaps
            if let note_id = zap.target.note_id {
                if let count = event_counts[note_id] {
                    event_counts[note_id] = count - 1
                }
                if let total = event_totals[note_id] {
                    event_totals[note_id] = total - zap.amount
                }
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
            case .note(let note_zap):
                let note_id = note_zap.note_id
                if our_zaps[note_id] == nil {
                    our_zaps[note_id] = [zap]
                } else {
                    insert_uniq_sorted_zap_by_amount(zaps: &(our_zaps[note_id]!), new_zap: zap)
                }
            case .profile:
                break
            }
        }
        
        // don't count tips to self. lame.
        guard zap.request.ev.pubkey != zap.target.pubkey else {
            return
        }
        
        if let note_id = zap.target.note_id {
            if event_counts[note_id] == nil {
                event_counts[note_id] = 0
            }

            if event_totals[note_id] == nil {
                event_totals[note_id] = 0
            }

            event_counts[note_id] = event_counts[note_id]! + 1
            event_totals[note_id] = event_totals[note_id]! + zap.amount

            notify(.update_stats(note_id: note_id))
        }
    }
}

func remove_zap(reqid: ZapRequestId, zapcache: Zaps, evcache: EventCache) {
    guard let zap = zapcache.remove_zap(reqid: reqid.reqid) else {
        return
    }
    evcache.get_cache_data(NoteId(zap.target.id)).zaps_model.remove(reqid: reqid)
}
