//
//  LikesModel.swift
//  damus
//
//  Created by William Casarin on 2023-01-11.
//

import Foundation


class ReactionsModel: ObservableObject {
    let state: DamusState
    let target: String
    let sub_id: String
    @Published var reactions: [NostrEvent]
    
    init (state: DamusState, target: String) {
        self.state = state
        self.target = target
        self.sub_id = UUID().description
        self.reactions = []
    }
    
    func get_filter() -> NostrFilter {
        var filter = NostrFilter.filter_kinds([7])
        filter.referenced_ids = [target]
        filter.limit = 500
        return filter
    }
    
    func subscribe() {
        let filter = get_filter()
        let filters = [filter]
        self.state.pool.subscribe(sub_id: sub_id, filters: filters, handler: handle_nostr_event)
    }
    
    func unsubscribe() {
        self.state.pool.unsubscribe(sub_id: sub_id)
    }
    
    func handle_event(relay_id: String, ev: NostrEvent) {
        guard ev.kind == 7 else {
            return
        }
        
        guard let reacted_to = last_etag(tags: ev.tags) else {
            return
        }
        
        guard reacted_to == self.target else {
            return
        }
        
        if insert_uniq_sorted_event(events: &self.reactions, new_ev: ev, cmp: { a, b in a.created_at < b.created_at } ) {
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
            load_profiles(profiles_subid: UUID().description, relay_id: relay_id, events: reactions, damus_state: state)
            break
        }
    }
}
