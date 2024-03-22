//
//  Timeline.swift
//  damus
//
//  Created by William Casarin on 2022-05-09.
//

import Foundation


class SearchModel: ObservableObject {
    let state: DamusState
    var events: EventHolder
    @Published var loading: Bool = false
    
    var search: NostrFilter
    let sub_id = UUID().description
    let profiles_subid = UUID().description
    let limit: UInt32 = 500
    
    init(state: DamusState, search: NostrFilter) {
        self.state = state
        self.search = search
        self.events = EventHolder(on_queue: { ev in
            preload_events(state: state, events: [ev])
        })
    }
    
    func filter_muted()  {
        self.events.filter {
            should_show_event(state: state, ev: $0)
        }
        self.objectWillChange.send()
    }
    
    func subscribe() {
        // since 1 month
        search.limit = self.limit
        search.kinds = [.text, .like, .longform]

        //likes_filter.ids = ref_events.referenced_ids!

        print("subscribing to search '\(search)' with sub_id \(sub_id)")
        state.pool.register_handler(sub_id: sub_id, handler: handle_event)
        loading = true
        state.pool.send(.subscribe(.init(filters: [search], sub_id: sub_id)))
    }
    
    func unsubscribe() {
        state.pool.unsubscribe(sub_id: sub_id)
        loading = false
        print("unsubscribing from search '\(search)' with sub_id \(sub_id)")
    }
    
    func add_event(_ ev: NostrEvent) {
        if !event_matches_filter(ev, filter: search) {
            return
        }
        
        guard should_show_event(state: state, ev: ev) else {
            return
        }
        
        if self.events.insert(ev) {
            objectWillChange.send()
        }
    }

    func handle_event(relay_id: RelayURL, ev: NostrConnectionEvent) {
        let (sub_id, done) = handle_subid_event(pool: state.pool, relay_id: relay_id, ev: ev) { sub_id, ev in
            if ev.is_textlike && ev.should_show_event {
                self.add_event(ev)
            }
        }
        
        guard done else {
            return
        }
        
        self.loading = false
        
        if sub_id == self.sub_id {
            guard let txn = NdbTxn(ndb: state.ndb) else { return }
            load_profiles(context: "search", profiles_subid: self.profiles_subid, relay_id: relay_id, load: .from_events(self.events.all_events), damus_state: state, txn: txn)
        }
    }
}

func event_matches_hashtag(_ ev: NostrEvent, hashtags: [String]) -> Bool {
    for tag in ev.tags {
        if tag_is_hashtag(tag) && hashtags.contains(tag[1].string()) {
            return true
        }
    }
    return false
}

func tag_is_hashtag(_ tag: Tag) -> Bool {
    // "hashtag" is deprecated, will remove in the future
    return tag.count >= 2 && tag[0].matches_char("t")
}

func event_matches_filter(_ ev: NostrEvent, filter: NostrFilter) -> Bool {
    if let hashtags = filter.hashtag {
        return event_matches_hashtag(ev, hashtags: hashtags)
    }
    return true
}

func handle_subid_event(pool: RelayPool, relay_id: RelayURL, ev: NostrConnectionEvent, handle: (String, NostrEvent) -> ()) -> (String?, Bool) {
    switch ev {
    case .ws_event:
        return (nil, false)
        
    case .nostr_event(let res):
        switch res {
        case .event(let ev_subid, let ev):
            handle(ev_subid, ev)
            return (ev_subid, false)
        
        case .ok:
            return (nil, false)

        case .notice(let note):
            if note.contains("Too many subscription filters") {
                // TODO: resend filters?
                pool.reconnect(to: [relay_id])
            }
            return (nil, false)
            
        case .eose(let subid):
            return (subid, true)

        case .auth:
            return (nil, false)
        }
    }
}
