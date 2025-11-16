//
//  EventHolder.swift
//  damus
//
//  Created by William Casarin on 2023-02-19.
//

import Foundation

/// Used for holding back events until they're ready to be displayed
class EventHolder: ObservableObject, ScrollQueue {
    private var has_event = Set<NoteId>()
    @Published var events: [NostrEvent]
    var filteredHolders: [UUID: FilteredHolder] = [:]
    var incoming: [NostrEvent]
    private(set) var should_queue = false
    var on_queue: ((NostrEvent) -> Void)?
    
    func set_should_queue(_ val: Bool) {
        self.should_queue = val
    }
    
    var queued: Int {
        return incoming.count
    }
    
    var all_events: [NostrEvent] {
        events + incoming
    }
    
    init(events: [NostrEvent] = [], incoming: [NostrEvent] = [], on_queue: ((NostrEvent) -> ())? = nil) {
        self.events = events
        self.incoming = incoming
        self.on_queue = on_queue
    }
    
    func filter(_ isIncluded: (NostrEvent) -> Bool) {
        self.events = self.events.filter(isIncluded)
        self.incoming = self.incoming.filter(isIncluded)
    }
    
    @MainActor
    func insert(_ ev: NostrEvent) -> Bool {
        if should_queue {
            return insert_queued(ev)
        } else {
            return insert_immediate(ev)
        }
    }
    
    @MainActor
    private func insert_immediate(_ ev: NostrEvent) -> Bool {
        if has_event.contains(ev.id) {
            return false
        }
        
        has_event.insert(ev.id)
        
        if insert_uniq_sorted_event_created(events: &self.events, new_ev: ev) {
            return true
        }
        for (id, filteredView) in self.filteredHolders {
            filteredView.insert(event: ev)
        }
        
        return false
    }
    
    private func insert_queued(_ ev: NostrEvent) -> Bool {
        if has_event.contains(ev.id) {
            return false
        }
        
        on_queue?(ev)
        
        has_event.insert(ev.id)
        
        incoming.append(ev)
        return true
    }
    
    func flush() {
        guard !incoming.isEmpty else {
            return
        }
        
        var changed = false
        for event in incoming {
            if insert_uniq_sorted_event_created(events: &events, new_ev: event) {
                changed = true
            }
            for (id, filteredHolder) in self.filteredHolders {
                filteredHolder.insert(event: event)
            }
        }
        
        if changed {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
        
        self.incoming = []
    }
    
    @MainActor
    func reset() {
        self.incoming = []
        self.events = []
        for (id, filteredHolder) in filteredHolders {
            filteredHolder.update(events: [])
        }
    }
    
    @MainActor
    func add(filteredHolder: FilteredHolder) -> UUID {
        let id = UUID()
        self.filteredHolders[id] = filteredHolder
        filteredHolder.update(events: self.events)
        return id
    }
    
    @MainActor
    func removeFilteredHolder(id: UUID) {
        self.filteredHolders[id] = nil
    }
    
    class FilteredHolder: ObservableObject {
        @Published private(set) var events: [NostrEvent]
        let filter: (NostrEvent) -> Bool
        
        init(filter: @escaping (NostrEvent) -> Bool) {
            self.events = []
            self.filter = filter
        }
        
        func update(events: [NostrEvent]) {
            self.events = events.filter(self.filter)
        }
        
        func insert(event: NostrEvent) {
            guard self.filter(event) else { return }
            var changed = false
            if insert_uniq_sorted_event_created(events: &events, new_ev: event) {
                changed = true
            }
            if changed {
                self.objectWillChange.send()
            }
        }
    }
}
