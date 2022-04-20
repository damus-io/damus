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
    let sub_id = UUID().description
    
    init(event: NostrEvent, pool: RelayPool) {
        self.event = event
        self.pool = pool
        add_event(event)
    }
    
    func unsubscribe() {
        print("unsubscribing from thread \(event.id) with sub_id \(sub_id)")
        self.pool.remove_handler(sub_id: sub_id)
        self.pool.send(.unsubscribe(sub_id))
    }
    
    func subscribe() {
        var ref_events = NostrFilter.filter_text
        var events = NostrFilter.filter_text

        // TODO: add referenced relays
        ref_events.referenced_ids = event.referenced_ids.map { $0.ref_id }
        ref_events.referenced_ids!.append(event.id)

        events.ids = ref_events.referenced_ids!

        print("subscribing to thread \(event.id) with sub_id \(sub_id)")
        pool.register_handler(sub_id: sub_id, handler: handle_event)
        pool.send(.subscribe(.init(filters: [ref_events, events], sub_id: sub_id)))
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
