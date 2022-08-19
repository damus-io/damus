//
//  Timeline.swift
//  damus
//
//  Created by William Casarin on 2022-05-09.
//

import Foundation


class SearchModel: ObservableObject {
    @Published var events: [NostrEvent] = []
    @Published var loading: Bool = false
    let pool: RelayPool
    var search: NostrFilter
    let sub_id = UUID().description
    let limit: UInt32 = 500
    
    init(pool: RelayPool, search: NostrFilter) {
        self.pool = pool
        self.search = search
    }
    
    func subscribe() {
        // since 1 month
        search.limit = self.limit
        search.kinds = [1,5,7]

        //likes_filter.ids = ref_events.referenced_ids!

        print("subscribing to search '\(search)' with sub_id \(sub_id)")
        pool.register_handler(sub_id: sub_id, handler: handle_event)
        loading = true
        pool.send(.subscribe(.init(filters: [search], sub_id: sub_id)))
    }
    
    func unsubscribe() {
        self.pool.unsubscribe(sub_id: sub_id)
        loading = false
        print("unsubscribing from search '\(search)' with sub_id \(sub_id)")
    }
    
    func add_event(_ ev: NostrEvent) {
        if !event_matches_filter(ev, filter: search) {
            return
        }
        
        if insert_uniq_sorted_event(events: &self.events, new_ev: ev, cmp: { $0.created_at > $1.created_at } ) {
            objectWillChange.send()
        }
    }
    
    func handle_event(relay_id: String, ev: NostrConnectionEvent) {
        let done = handle_subid_event(pool: pool, sub_id: sub_id, relay_id: relay_id, ev: ev) { ev in
            if ev.known_kind == .text && ev.should_show_event {
                self.add_event(ev)
            }
        }
        
        if done {
            loading = false
        }
    }
}

func event_matches_hashtag(_ ev: NostrEvent, hashtags: [String]) -> Bool {
    for tag in ev.tags {
        if tag_is_hashtag(tag) && hashtags.contains(tag[1]) {
            return true
        }
    }
    return false
}

func event_matches_filter(_ ev: NostrEvent, filter: NostrFilter) -> Bool {
    if let hashtags = filter.hashtag {
        return event_matches_hashtag(ev, hashtags: hashtags)
    }
    return true
}

func handle_subid_event(pool: RelayPool, sub_id: String, relay_id: String, ev: NostrConnectionEvent, handle: (NostrEvent) -> ()) -> Bool {
    switch ev {
    case .ws_event:
        break
    case .nostr_event(let res):
        switch res {
        case .event(let ev_subid, let ev):
            if ev_subid == sub_id {
                handle(ev)
            }
            break

        case .notice(let note):
            if note.contains("Too many subscription filters") {
                // TODO: resend filters?
                pool.reconnect(to: [relay_id])
            }
            break
            
        case .eose:
            return true
        }
    }
    
    return false
}
