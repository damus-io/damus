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
    @Published var events: [NostrEvent] = []
    @Published var event_map: [String: Int] = [:]
    var replies: ReplyMap = ReplyMap()
    
    let pool: RelayPool
    var sub_id = UUID().description
    
    init(ev: NostrEvent, pool: RelayPool) {
        self.event = ev
        self.pool = pool
        subscribe()
    }
    
    deinit {
        unsubscribe()
    }
    
    func unsubscribe() {
        self.pool.unsubscribe(sub_id: sub_id)
        print("unsubscribing from thread \(event.id) with sub_id \(sub_id)")
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
    
    func set_active_event(_ ev: NostrEvent) {
        if should_resubscribe(ev) {
            unsubscribe()
            self.event = ev
            add_event(ev)
            subscribe()
        } else {
            self.event = ev
            if events.count == 0 {
                add_event(ev)
            }
        }
    }
    
    func subscribe() {
        let kinds: [Int] = [1, 5, 6]
        var ref_events = NostrFilter.filter_kinds(kinds)
        var events_filter = NostrFilter.filter_kinds(kinds)

        // TODO: add referenced relays
        ref_events.referenced_ids = event.referenced_ids.map { $0.ref_id }
        ref_events.referenced_ids!.append(event.id)

        events_filter.ids = ref_events.referenced_ids!

        print("subscribing to thread \(event.id) with sub_id \(sub_id)")
        pool.register_handler(sub_id: sub_id, handler: handle_event)
        pool.send(.subscribe(.init(filters: [ref_events, events_filter], sub_id: sub_id)))
    }
    
    func lookup(_ event_id: String) -> NostrEvent? {
        if let i = event_map[event_id] {
            return events[i]
        }
        return nil
    }
    
    func add_event(_ ev: NostrEvent) {
        if event_map[ev.id] != nil {
            return
        }
        
        if let reply_id = ev.find_direct_reply() {
            self.replies.add(id: ev.id, reply_id: reply_id)
        }
        
        self.events.append(ev)
        self.events = self.events.sorted { $0.created_at < $1.created_at }
        var i: Int = 0
        for ev in events {
            self.event_map[ev.id] = i
            i += 1
        }
    }

    func handle_event(relay_id: String, ev: NostrConnectionEvent) {
        switch ev {
        case .ws_event:
            break
        case .nostr_event(let res):
            switch res {
            case .event(let sub_id, let ev):
                if sub_id == self.sub_id {
                    add_event(ev)
                }

            case .notice(let note):
                if note.contains("Too many subscription filters") {
                    // TODO: resend filters?
                    pool.reconnect(to: [relay_id])
                }
                break
            }
        }
    }

}
