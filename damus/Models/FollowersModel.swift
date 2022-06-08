//
//  FollowersModel.swift
//  damus
//
//  Created by William Casarin on 2022-05-26.
//

import Foundation

class FollowersModel: ObservableObject {
    let damus_state: DamusState
    let target: String
    var needs_sub: Bool = true
    
    @Published var contacts: [String] = []
    var has_contact: Set<String> = Set()
    
    let sub_id: String = UUID().description
    
    init(damus_state: DamusState, target: String) {
        self.damus_state = damus_state
        self.target = target
    }
    
    func get_filter() -> NostrFilter {
        var filter = NostrFilter.filter_contacts
        filter.pubkeys = [target]
        return filter
    }
    
    func subscribe() {
        let filter = get_filter()
        let filters = [filter]
        print_filters(relay_id: "following", filters: [filters])
        self.damus_state.pool.subscribe(sub_id: sub_id, filters: filters, handler: handle_event)
    }
    
    func unsubscribe() {
        self.damus_state.pool.unsubscribe(sub_id: sub_id)
    }
    
    func handle_contact_event(_ ev: NostrEvent) {
        if has_contact.contains(ev.pubkey) {
            return
        }
        process_contact_event(
            pool: damus_state.pool,
            contacts: damus_state.contacts,
            pubkey: damus_state.pubkey, ev: ev
        )
        contacts.append(ev.pubkey)
        has_contact.insert(ev.pubkey)
    }
    
    func handle_event(relay_id: String, ev: NostrConnectionEvent) {
        switch ev {
        case .ws_event:
            break
        case .nostr_event(let nev):
            switch nev {
            case .event(_, let ev):
                if ev.kind == 3 {
                    handle_contact_event(ev)
                }
            case .notice(let msg):
                print("followingmodel notice: \(msg)")
            case .eose:
                break
            }
        }
    }
}
