//
//  Timeline.swift
//  damus
//
//  Created by William Casarin on 2022-05-09.
//

import Foundation


class SearchModel: ObservableObject {
    var events: EventHolder = EventHolder()
    @Published var loading: Bool = false
    @Published var channel_name: String? = nil
    
    let pool: RelayPool
    var search: NostrFilter
    let contacts: Contacts
    let sub_id = UUID().description
    let limit: UInt32 = 500
    
    init(contacts: Contacts, pool: RelayPool, search: NostrFilter) {
        self.contacts = contacts
        self.pool = pool
        self.search = search
    }
    
    func filter_muted()  {
        self.events.filter { should_show_event(contacts: contacts, ev: $0) }
        self.objectWillChange.send()
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
        
        guard should_show_event(contacts: contacts, ev: ev) else {
            return
        }
        
        if self.events.insert(ev) {
            objectWillChange.send()
        }
    }
    
    func handle_channel_create(_ ev: NostrEvent) {
        self.channel_name = ev.content
        return
    }
    
    func handle_channel_meta(_ ev: NostrEvent) {
        self.channel_name = ev.content
        return
    }
    
    func handle_event(relay_id: String, ev: NostrConnectionEvent) {
        let (_, done) = handle_subid_event(pool: pool, relay_id: relay_id, ev: ev) { sub_id, ev in
            if ev.is_textlike && ev.should_show_event {
                self.add_event(ev)
            } else if ev.known_kind == .channel_create {
                handle_channel_create(ev)
            } else if ev.known_kind == .channel_meta {
                handle_channel_meta(ev)
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

func tag_is_hashtag(_ tag: [String]) -> Bool {
    // "hashtag" is deprecated, will remove in the future
    return tag.count >= 2 && (tag[0] == "hashtag" || tag[0] == "t")
}

func has_hashtag(_ tags: [[String]], hashtag: String) -> Bool {
    for tag in tags {
        if tag_is_hashtag(tag) && tag[1] == hashtag {
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

func handle_subid_event(pool: RelayPool, relay_id: String, ev: NostrConnectionEvent, handle: (String, NostrEvent) -> ()) -> (String?, Bool) {
    switch ev {
    case .ws_event:
        return (nil, false)
        
    case .nostr_event(let res):
        switch res {
        case .event(let ev_subid, let ev):
            handle(ev_subid, ev)
            return (ev_subid, false)

        case .notice(let note):
            if note.contains("Too many subscription filters") {
                // TODO: resend filters?
                pool.reconnect(to: [relay_id])
            }
            return (nil, false)
            
        case .eose(let subid):
            return (subid, true)
        }
    }
}
