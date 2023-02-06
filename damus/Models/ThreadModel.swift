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
    
    let damus_state: DamusState
    
    let profiles_subid = UUID().description
    var base_subid = UUID().description
   
    init(evid: String, damus_state: DamusState) {
        self.damus_state = damus_state
        self.initial_event = .event_id(evid)
    }
    
    init(event: NostrEvent, damus_state: DamusState) {
        self.damus_state = damus_state
        self.initial_event = .event(event)
    }
    
    func unsubscribe() {
        self.damus_state.pool.unsubscribe(sub_id: base_subid)
        print("unsubscribing from thread \(initial_event.id) with sub_id \(base_subid)")
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
        var ref_events = NostrFilter()
        var events_filter = NostrFilter()
        //var likes_filter = NostrFilter.filter_kinds(7])

        // TODO: add referenced relays
        switch self.initial_event {
        case .event(let ev):
            ref_events.referenced_ids = ev.referenced_ids.map { $0.ref_id }
            ref_events.referenced_ids?.append(ev.id)
            ref_events.limit = 50
            events_filter.ids = ref_events.referenced_ids ?? []
            events_filter.limit = 100
            events_filter.ids?.append(ev.id)
        case .event_id(let evid):
            ref_events.referenced_ids = [evid]
            ref_events.limit = 50
            events_filter.ids = [evid]
            events_filter.limit = 100
        }

        //likes_filter.ids = ref_events.referenced_ids!

        print("subscribing to thread \(initial_event.id) with sub_id \(base_subid)")
        damus_state.pool.register_handler(sub_id: base_subid, handler: handle_event)
        loading = true
        damus_state.pool.send(.subscribe(.init(filters: [ref_events, events_filter], sub_id: base_subid)))
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
    
    func handle_channel_meta(_ ev: NostrEvent) {
        guard let meta: ChatroomMetadata = decode_json(ev.content) else {
            return
        }
        
        notify(.chatroom_meta, meta)
    }
    
    func handle_event(relay_id: String, ev: NostrConnectionEvent) {
        
        let (sub_id, done) = handle_subid_event(pool: damus_state.pool, relay_id: relay_id, ev: ev) { sid, ev in
            guard sid == base_subid || sid == profiles_subid else {
                return
            }
            
            if ev.known_kind == .metadata {
                process_metadata_event(our_pubkey: damus_state.pubkey, profiles: damus_state.profiles, ev: ev)
            } else if ev.is_textlike {
                self.add_event(ev, privkey: self.damus_state.keypair.privkey)
            } else if ev.known_kind == .channel_meta || ev.known_kind == .channel_create {
                handle_channel_meta(ev)
            }
        }
        
        guard done && (sub_id == base_subid || sub_id == profiles_subid) else {
            return
        }
        
        if (events.contains { ev in ev.id == initial_event.id }) {
            loading = false
        }
        
        if sub_id == self.base_subid {
            load_profiles(profiles_subid: self.profiles_subid, relay_id: relay_id, events: events, damus_state: damus_state)
        }
    }

}
