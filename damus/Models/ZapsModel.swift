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
    
    let zaps_subid = UUID().description
    let profiles_subid = UUID().description
    
    init(state: DamusState, target: ZapTarget) {
        self.state = state
        self.target = target
    }
    
    var zaps: [Zap] {
        return state.events.lookup_zaps(target: target)
    }
    
    func subscribe() {
        var filter = NostrFilter.filter_kinds([NostrKind.zap.rawValue])
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
        
        switch resp {
        case .ok:
            break
        case .notice:
            break
        case .eose:
            let events = state.events.lookup_zaps(target: target).map { $0.request_ev }
            load_profiles(profiles_subid: profiles_subid, relay_id: relay_id, load: .from_events(events), damus_state: state)
        case .event(_, let ev):
            guard ev.kind == 9735 else {
                return
            }
            
            if let zap = state.zaps.zaps[ev.id] {
                if state.events.store_zap(zap: zap) {
                    objectWillChange.send()
                }
            } else {
                guard let zapper = state.profiles.lookup_zapper(pubkey: target.pubkey) else {
                    return
                }
                
                guard let zap = Zap.from_zap_event(zap_ev: ev, zapper: zapper, our_privkey: state.keypair.privkey) else {
                    return
                }
                
                if self.state.add_zap(zap: zap) {
                    objectWillChange.send()
                }
            }
        }
        
        
        
    }
}
