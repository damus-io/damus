//
//  ThreadModel.swift
//  damus
//
//  Created by William Casarin on 2022-04-19.
//

import Foundation

enum InitialEvent {
    case event(NostrEvent)
    case event_id(String)
    
    var is_event_id: String? {
        if case .event_id(let evid) = self {
            return evid
        }
        return nil
    }
    
    var id: String {
        switch self {
        case .event(let ev):
            return ev.id
        case .event_id(let evid):
            return evid
        }
    }
}

/// manages the lifetime of a thread
class ThreadModel: ObservableObject {
    let privkey: String?
    let kind: Int
    @Published var initial_event: InitialEvent
    @Published var events: [NostrEvent] = []
    @Published var event_map: [String: Int] = [:]
    @Published var loading: Bool = false
    
    var replies: ReplyMap = ReplyMap()
    
    var event: NostrEvent? {
        switch initial_event {
        case .event(let ev):
            return ev
        case .event_id(let evid):
            for event in events {
                if event.id == evid {
                    return event
                }
            }
            return nil
        }
    }
    
    let pool: RelayPool
    var sub_id = UUID().description
   
    init(evid: String, pool: RelayPool, privkey: String?) {
        self.pool = pool
        self.initial_event = .event_id(evid)
        self.privkey = privkey
        self.kind = NostrKind.text.rawValue
    }
    
    init(event: NostrEvent, pool: RelayPool, privkey: String?) {
        self.pool = pool
        self.initial_event = .event(event)
        self.privkey = privkey
        self.kind = NostrKind.text.rawValue
    }
    
    init(event: NostrEvent, pool: RelayPool, privkey: String?, kind: Int) {
        self.pool = pool
        self.initial_event = .event(event)
        self.privkey = privkey
        self.kind = kind
    }
    
    func unsubscribe() {
        self.pool.unsubscribe(sub_id: sub_id)
        print("unsubscribing from thread \(initial_event.id) with sub_id \(sub_id)")
    }
    
    func reset_events() {
        self.events.removeAll()
        self.event_map.removeAll()
        self.replies.replies.removeAll()
    }
    
    func should_resubscribe(_ ev_b: NostrEvent) -> Bool {
        if self.events.count == 0 {
            return true
        }
        
        if ev_b.is_root_event() {
            return false
        }

        // rough heuristic to save us from resubscribing all the time
        //return ev_b.count_ids() != self.event.count_ids()
        return true
    }
    
    func set_active_event(_ ev: NostrEvent, privkey: String?) {
        if should_resubscribe(ev) {
            unsubscribe()
            self.initial_event = .event(ev)
            subscribe()
        } else {
            self.initial_event = .event(ev)
            if events.count == 0 {
                add_event(ev, privkey: privkey)
            }
        }
    }
    
    func subscribe() {
        var ref_events = NostrFilter.filter_kinds([self.kind,5,6,7])
        var events_filter = NostrFilter.filter_kinds([self.kind])
        //var likes_filter = NostrFilter.filter_kinds(7])

        // TODO: add referenced relays
        switch self.initial_event {
        case .event(let ev):
            ref_events.referenced_ids = ev.referenced_ids.map { $0.ref_id }
            ref_events.referenced_ids?.append(ev.id)
            events_filter.ids = ref_events.referenced_ids!
            events_filter.ids?.append(ev.id)
        case .event_id(let evid):
            events_filter.ids = [evid]
            ref_events.referenced_ids = [evid]
        }

        //likes_filter.ids = ref_events.referenced_ids!

        print("subscribing to thread \(initial_event.id) with sub_id \(sub_id)")
        pool.register_handler(sub_id: sub_id, handler: handle_event)
        loading = true
        pool.send(.subscribe(.init(filters: [ref_events, events_filter], sub_id: sub_id)))
    }
    
    func lookup(_ event_id: String) -> NostrEvent? {
        if let i = event_map[event_id] {
            return events[i]
        }
        return nil
    }
    
    func add_event(_ ev: NostrEvent, privkey: String?) {
        guard ev.should_show_event else {
            return
        }
        
        if event_map[ev.id] != nil {
            return
        }
        
        for reply in ev.direct_replies(privkey) {
            self.replies.add(id: ev.id, reply_id: reply.ref_id)
        }
        
        if insert_uniq_sorted_event(events: &self.events, new_ev: ev, cmp: { $0.created_at < $1.created_at }) {
            objectWillChange.send()
        }
        //self.events.append(ev)
        //self.events = self.events.sorted { $0.created_at < $1.created_at }
        
        var i: Int = 0
        for ev in events {
            self.event_map[ev.id] = i
            i += 1
        }
        
        if let evid = self.initial_event.is_event_id {
            if ev.id == evid {
                // this should trigger a resubscribe...
                set_active_event(ev, privkey: privkey)
            }
        }
        
    }

    func handle_event(relay_id: String, ev: NostrConnectionEvent) {
        let done = handle_subid_event(pool: pool, sub_id: sub_id, relay_id: relay_id, ev: ev) { ev in
            if ev.known_kind == .text {
                self.add_event(ev, privkey: self.privkey)
            }
        }
        
        if done {
            loading = false
        }
    }

}
