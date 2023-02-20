//
//  EventHolder.swift
//  damus
//
//  Created by William Casarin on 2023-02-19.
//

import Foundation

/// Used for holding back events until they're ready to be displayed
class EventHolder: ObservableObject {
    private var has_event: Set<String>
    @Published var events: [NostrEvent]
    @Published var incoming: [NostrEvent]
    @Published var should_queue: Bool
    
    var queued: Int {
        return incoming.count
    }
    
    var has_incoming: Bool {
        return queued > 0
    }
    
    var all_events: [NostrEvent] {
        events + incoming
    }
    
    init() {
        self.should_queue = false
        self.events = []
        self.incoming = []
        self.has_event = Set()
    }
    
    init(events: [NostrEvent], incoming: [NostrEvent]) {
        self.should_queue = false
        self.events = events
        self.incoming = incoming
        self.has_event = Set()
    }
    
    func filter(_ isIncluded: (NostrEvent) -> Bool) {
        self.events = self.events.filter(isIncluded)
        self.incoming = self.incoming.filter(isIncluded)
    }
    
    func insert(_ ev: NostrEvent) -> Bool {
        if should_queue {
            return insert_queued(ev)
        } else {
            return insert_immediate(ev)
        }
    }
    
    private func insert_immediate(_ ev: NostrEvent) -> Bool {
        if has_event.contains(ev.id) {
            return false
        }
        
        has_event.insert(ev.id)
        
        if insert_uniq_sorted_event_created(events: &self.events, new_ev: ev) {
            return true
        }
        
        return false
    }
    
    private func insert_queued(_ ev: NostrEvent) -> Bool {
        if has_event.contains(ev.id) {
            return false
        }
        
        has_event.insert(ev.id)
        
        incoming.append(ev)
        return true
    }
    
    func flush() {
        var changed = false
        for event in incoming {
            if insert_uniq_sorted_event_created(events: &events, new_ev: event) {
                changed = true
            }
        }
        
        if changed {
            self.objectWillChange.send()
        }
        
        self.incoming = []
    }
}
