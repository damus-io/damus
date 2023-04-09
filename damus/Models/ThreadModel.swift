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
    @Published var event: NostrEvent
    var event_map: Set<NostrEvent>
    
    @Published var loading: Bool = false

    var replies: ReplyMap = ReplyMap()
    
    init(event: NostrEvent, damus_state: DamusState) {
        self.damus_state = damus_state
        self.event_map = Set()
        self.event = event
        add_event(event, privkey: nil)
    }
    
    let damus_state: DamusState
    
    let profiles_subid = UUID().description
    let base_subid = UUID().description
    let meta_subid = UUID().description
    
    var subids: [String] {
        return [profiles_subid, base_subid, meta_subid]
    }
    
    func unsubscribe() {
        self.damus_state.pool.remove_handler(sub_id: base_subid)
        self.damus_state.pool.remove_handler(sub_id: meta_subid)
        self.damus_state.pool.remove_handler(sub_id: profiles_subid)
        self.damus_state.pool.unsubscribe(sub_id: base_subid)
        self.damus_state.pool.unsubscribe(sub_id: meta_subid)
        self.damus_state.pool.unsubscribe(sub_id: profiles_subid)
        print("unsubscribing from thread \(event.id) with sub_id \(base_subid)")
    }
    
    @discardableResult
    func set_active_event(_ ev: NostrEvent, privkey: String?) -> Bool {
        self.event = ev
        add_event(ev, privkey: privkey)
        
        //self.objectWillChange.send()
        return false
    }
    
    func subscribe() {
        var meta_events = NostrFilter()
        var event_filter = NostrFilter()
        var ref_events = NostrFilter()
        //var likes_filter = NostrFilter.filter_kinds(7])

        let thread_id = event.thread_id(privkey: nil)
        
        ref_events.referenced_ids = [thread_id, event.id]
        ref_events.kinds = [1]
        ref_events.limit = 1000
        
        event_filter.ids = [thread_id, event.id]
        
        meta_events.referenced_ids = [event.id]
        meta_events.kinds = [9735, 1, 6, 7]
        meta_events.limit = 1000
        
        /*
        if let last_ev = self.events.last {
            if last_ev.created_at <= Int64(Date().timeIntervalSince1970) {
                ref_events.since = last_ev.created_at
            }
        }
         */
        
        let base_filters = [event_filter, ref_events]
        let meta_filters = [meta_events]

        print("subscribing to thread \(event.id) with sub_id \(base_subid)")
        loading = true
        damus_state.pool.subscribe(sub_id: base_subid, filters: base_filters, handler: handle_event)
        damus_state.pool.subscribe(sub_id: meta_subid, filters: meta_filters, handler: handle_event)
    }
    
    func add_event(_ ev: NostrEvent, privkey: String?) {
        if event_map.contains(ev) {
            return
        }
        
        let the_ev = damus_state.events.upsert(ev)
        damus_state.replies.count_replies(the_ev)
        damus_state.events.add_replies(ev: the_ev)
        
        event_map.insert(ev)
        objectWillChange.send()
    }
    
    func handle_event(relay_id: String, ev: NostrConnectionEvent) {
        
        let (sub_id, done) = handle_subid_event(pool: damus_state.pool, relay_id: relay_id, ev: ev) { sid, ev in
            guard subids.contains(sid) else {
                return
            }
            
            if ev.known_kind == .metadata {
                process_metadata_event(our_pubkey: damus_state.pubkey, profiles: damus_state.profiles, ev: ev)
            } else if ev.is_textlike {
                self.add_event(ev, privkey: self.damus_state.keypair.privkey)
            }
        }
        
        guard done, let sub_id, subids.contains(sub_id) else {
            return
        }
        
        if event_map.contains(event) {
            loading = false
        }
        
        if sub_id == self.base_subid {
            load_profiles(profiles_subid: self.profiles_subid, relay_id: relay_id, load: .from_events(Array(event_map)), damus_state: damus_state)
        }
    }

}
