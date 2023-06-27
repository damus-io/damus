//
//  ThreadModel.swift
//  damus
//
//  Created by William Casarin on 2022-04-19.
//

import Foundation

/// manages the lifetime of a thread
class ThreadModel: ObservableObject {
    @Published var event: NostrEvent
    let original_event: NostrEvent
    var event_map: Set<NostrEvent>
    
    init(event: NostrEvent, damus_state: DamusState) {
        self.damus_state = damus_state
        self.event_map = Set()
        self.event = event
        self.original_event = event
        add_event(event)
    }
    
    var is_original: Bool {
        return original_event.id == event.id
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
    func set_active_event(_ ev: NostrEvent) -> Bool {
        self.event = ev
        add_event(ev)
        
        //self.objectWillChange.send()
        return false
    }
    
    func subscribe() {
        var meta_events = NostrFilter()
        var event_filter = NostrFilter()
        var ref_events = NostrFilter()

        let thread_id = event.thread_id(privkey: nil)
        
        ref_events.referenced_ids = [thread_id, event.id]
        ref_events.kinds = [.text]
        ref_events.limit = 1000
        
        event_filter.ids = [thread_id, event.id]
        
        meta_events.referenced_ids = [event.id]

        var kinds: [NostrKind] = [.zap, .text, .boost]
        if !damus_state.settings.onlyzaps_mode {
            kinds.append(.like)
        }
        meta_events.kinds = kinds

        meta_events.limit = 1000
        
        let base_filters = [event_filter, ref_events]
        let meta_filters = [meta_events]

        print("subscribing to thread \(event.id) with sub_id \(base_subid)")
        damus_state.pool.subscribe(sub_id: base_subid, filters: base_filters, handler: handle_event)
        damus_state.pool.subscribe(sub_id: meta_subid, filters: meta_filters, handler: handle_event)
    }
    
    func add_event(_ ev: NostrEvent) {
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
                process_metadata_event(events: damus_state.events, our_pubkey: damus_state.pubkey, profiles: damus_state.profiles, ev: ev)
            } else if ev.known_kind == .zap {
                process_zap_event(damus_state: damus_state, ev: ev) { zap in
                    
                }
            } else if ev.is_textlike {
                self.add_event(ev)
            }
        }
        
        guard done, let sub_id, subids.contains(sub_id) else {
            return
        }
        
        if sub_id == self.base_subid {
            load_profiles(profiles_subid: self.profiles_subid, relay_id: relay_id, load: .from_events(Array(event_map)), damus_state: damus_state)
        }
    }

}


func get_top_zap(events: EventCache, evid: String) -> Zapping? {
    return events.get_cache_data(evid).zaps_model.zaps.first(where: { zap in
        !zap.request.marked_hidden
    })
}
