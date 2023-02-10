//
//  ZapsModel.swift
//  damus
//
//  Created by William Casarin on 2023-02-10.
//

import Foundation

class ZapsModel: ObservableObject {
    let state: DamusState
    let target: ZapTarget
    var zaps: [Zap]
    
    let zaps_subid = UUID().description
    
    init(state: DamusState, target: ZapTarget) {
        self.state = state
        self.target = target
        self.zaps = []
    }
    
    func subscribe() {
        var filter = NostrFilter.filter_kinds([9735])
        switch target {
        case .profile(let profile_id):
            filter.pubkeys = [profile_id]
        case .note(let note_target):
            filter.referenced_ids = [note_target.note_id]
        }
        state.pool.subscribe(sub_id: zaps_subid, filters: [filter], handler: handle_event)
    }
    
    func unsubscribe() {
        state.pool.unsubscribe(sub_id: zaps_subid)
    }
    
    func handle_event(relay_id: String, conn_ev: NostrConnectionEvent) {
        guard case .nostr_event(let resp) = conn_ev else {
            return
        }
        
        guard resp.subid == zaps_subid else {
            return
        }
        
        guard case .event(_, let ev) = resp else {
            return
        }
        
        guard ev.kind == 9735 else {
            return
        }
        
        if let zap = state.zaps.zaps[ev.id] {
            if insert_uniq_sorted_zap(zaps: &zaps, new_zap: zap) {
                objectWillChange.send()
            }
        } else {
            guard let zapper = state.profiles.lookup_zapper(pubkey: target.pubkey) else {
                return
            }
            
            guard let zap = Zap.from_zap_event(zap_ev: ev, zapper: zapper) else {
                return
            }
            
            state.zaps.add_zap(zap: zap)
            
            if insert_uniq_sorted_zap(zaps: &zaps, new_zap: zap) {
                objectWillChange.send()
            }
        }
        
        
    }
}
