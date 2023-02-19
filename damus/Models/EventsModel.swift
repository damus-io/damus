//
//  EventsModel.swift
//  damus
//
//  Created by William Casarin on 2022-05-24.
//

import Foundation


class EventsModel: ObservableObject {
    let state: DamusState
    let target: String
    let kind: NostrKind
    let sub_id = UUID().uuidString
    let profiles_id = UUID().uuidString
    
    @Published var events: [NostrEvent] = []
    
    init(state: DamusState, target: String, kind: NostrKind) {
        self.state = state
        self.target = target
        self.kind = kind
    }
    
    private func get_filter() -> NostrFilter {
        var filter = NostrFilter.filter_kinds([kind.rawValue])
        filter.referenced_ids = [target]
        filter.limit = 500
        return filter
    }
    
    func subscribe() {
        state.pool.subscribe(sub_id: sub_id,
                             filters: [get_filter()],
                             handler: handle_nostr_event)
    }
    
    func unsubscribe() {
        state.pool.unsubscribe(sub_id: sub_id)
    }
    
    private func handle_event(relay_id: String, ev: NostrEvent) {
        guard ev.kind == kind.rawValue else {
            return
        }
        
        guard last_etag(tags: ev.tags) == target else {
            return
        }
        
        if insert_uniq_sorted_event(events: &self.events, new_ev: ev, cmp: { a, b in a.created_at < b.created_at } ) {
            objectWillChange.send()
        }
    }
    
    func handle_nostr_event(relay_id: String, ev: NostrConnectionEvent) {
        guard case .nostr_event(let nev) = ev else {
            return
        }
        
        switch nev {
        case .event(_, let ev):
            handle_event(relay_id: relay_id, ev: ev)
        case .notice(_):
            break
        case .eose(_):
            load_profiles(profiles_subid: profiles_id, relay_id: relay_id, events: events, damus_state: state)
        }
    }
}
