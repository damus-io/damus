//
//  FollowingModel.swift
//  damus
//
//  Created by William Casarin on 2022-05-24.
//

import Foundation

class FollowingModel: ObservableObject {
    let damus_state: DamusState
    var needs_sub: Bool = true
    
    var has_contact: Set<String> = Set()
    let contacts: [String]
    
    let sub_id: String = UUID().description
    
    init(damus_state: DamusState, contacts: [String]) {
        self.damus_state = damus_state
        self.contacts = contacts
    }
    
    func get_filter() -> NostrFilter {
        var f = NostrFilter.filter_kinds([0])
        f.authors = self.contacts.reduce(into: Array<String>()) { acc, pk in
            // don't fetch profiles we already have
            if damus_state.profiles.lookup(id: pk) != nil {
                return
            }
            acc.append(pk)
        }
        return f
    }
    
    func subscribe() {
        let filter = get_filter()
        if (filter.authors?.count ?? 0) == 0 {
            needs_sub = false
            return
        }
        let filters = [filter]
        print_filters(relay_id: "following", filters: [filters])
        self.damus_state.pool.subscribe(sub_id: sub_id, filters: filters, handler: handle_event)
    }
    
    func unsubscribe() {
        if !needs_sub {
            return
        }
        print("unsubscribing from following \(sub_id)")
        self.damus_state.pool.unsubscribe(sub_id: sub_id)
    }
    
    func handle_event(relay_id: String, ev: NostrConnectionEvent) {
        switch ev {
        case .ws_event:
            break
        case .nostr_event(let nev):
            switch nev {
            case .event(_, let ev):
                if ev.kind == 0 {
                    process_metadata_event(profiles: damus_state.profiles, ev: ev)
                }
            case .notice(let msg):
                print("followingmodel notice: \(msg)")
            }
        }
    }
}
