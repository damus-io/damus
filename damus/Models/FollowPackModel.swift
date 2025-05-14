//
//  FollowPackModel.swift
//  damus
//
//  Created by eric on 6/5/25.
//

import Foundation


class FollowPackModel: ObservableObject {
    var events: EventHolder
    @Published var loading: Bool = false
    
    let damus_state: DamusState
    let subid = UUID().description
    let limit: UInt32 = 500
    
    init(damus_state: DamusState) {
        self.damus_state = damus_state
        self.events = EventHolder(on_queue: { ev in
            preload_events(state: damus_state, events: [ev])
        })
    }
    
    func subscribe(follow_pack_users: [Pubkey]) {
        loading = true
        let to_relays = determine_to_relays(pool: damus_state.nostrNetwork.pool, filters: damus_state.relay_filters)
        var filter = NostrFilter(kinds: [.text, .chat])
        filter.until = UInt32(Date.now.timeIntervalSince1970)
        filter.authors = follow_pack_users
        filter.limit = 500
        
        damus_state.nostrNetwork.pool.subscribe(sub_id: subid, filters: [filter], handler: handle_event, to: to_relays)
    }

    func unsubscribe(to: RelayURL? = nil) {
        loading = false
        damus_state.nostrNetwork.pool.unsubscribe(sub_id: subid, to: to.map { [$0] })
    }

    func handle_event(relay_id: RelayURL, conn_ev: NostrConnectionEvent) {
        guard case .nostr_event(let event) = conn_ev else {
            return
        }
        
        switch event {
        case .event(let sub_id, let ev):
            guard sub_id == self.subid else {
                return
            }
            if ev.is_textlike && should_show_event(state: damus_state, ev: ev) && !ev.is_reply()
            {
                if self.events.insert(ev) {
                    self.objectWillChange.send()
                }
            }
        case .notice(let msg):
            print("follow pack notice: \(msg)")
        case .ok:
            break
        case .eose(let sub_id):
            loading = false
            
            if sub_id == self.subid {
                unsubscribe(to: relay_id)
                
                guard let txn = NdbTxn(ndb: damus_state.ndb) else { return }
            }

            break
        case .auth:
            break
        }
    }
}

