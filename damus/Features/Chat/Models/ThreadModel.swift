//
//  ThreadModel.swift
//  damus
//
//  Created by William Casarin on 2022-04-19.
//

import Foundation

/// manages the lifetime of a thread in a thread view such as `ChatroomThreadView`
/// Makes a subscription to the relay pool to get events related to the thread
/// It also keeps track of a selected event in the thread, and can pinpoint all of its parents and reply chain
@MainActor
class ThreadModel: ObservableObject {
    /// The original event where this thread was loaded from
    /// We use this to know the starting point from which we try to load the rest of the thread
    /// This is immutable because this is our starting point of the thread, and we don't expect this to ever change during the lifetime of a thread view
    let original_event: NostrEvent
    /// A map of events, the reply chain, etc
    /// This can be read by the view, but it can only be updated internally, because it is this classes' responsibility to ensure we load the proper events
    @Published private(set) var event_map: ThreadEventMap
    /// The currently selected event
    /// Can only be directly changed internally. Views should set this via the `select` methods
    @Published private(set) var selected_event: NostrEvent
    
    /// All of the parent events of `selected_event` in the thread, sorted from the highest level in the thread (The root of the thread), down to the direct parent
    ///
    /// ## Implementation notes
    ///
    /// This is a computed property because we then don't need to worry about keeping things in sync
    var parent_events: [NostrEvent] {
        // This block of code helps ensure `ThreadEventMap` stays in sync with `EventCache`
        let parent_events_from_cache = damus_state.events.parent_events(event: selected_event, keypair: damus_state.keypair)
        for parent_event in parent_events_from_cache {
            add_event(
                parent_event,
                keypair: damus_state.keypair,
                look_for_parent_events: false,   // We have all parents we need for now
                publish_changes: false           // Publishing changes during a view render is problematic
            )
        }
        
        return parent_events_from_cache
    }
    /// All of the direct and indirect replies of `selected_event` in the thread. sorted chronologically
    ///
    /// ## Implementation notes
    ///
    /// This is a computed property because we then don't need to worry about keeping things in sync
    var sorted_child_events: [NostrEvent] {
        event_map.sorted_recursive_child_events(of: selected_event).filter({
            should_show_event(event: $0, damus_state: damus_state)    // Hide muted events from chatroom conversation
        })
    }
    
    /// The damus state, needed to access the relay pool and load the thread events
    let damus_state: DamusState
    
    private var listener: Task<Void, Never>?
    
    
    // MARK: Initialization
    
    /// Initialize this model
    ///
    /// You should also call `subscribe()` to start loading thread events from the relay pool.
    /// This is done manually to ensure we only load stuff when needed (e.g. when a view appears)
    init(event: NostrEvent, damus_state: DamusState) {
        self.damus_state = damus_state
        self.event_map = ThreadEventMap()
        self.original_event = event
        self.selected_event = event
        add_event(event, keypair: damus_state.keypair)
    }

    /// All events in the thread, sorted in chronological order
    var events: [NostrEvent] {
        return event_map.sorted_events
    }
    
    
    // MARK: Relay pool subscription management
    
    /// Subscribe to events in this thread. Call this when loading the view.
    func subscribe() {
        var meta_events = NostrFilter()
        var quote_events = NostrFilter()
        var event_filter = NostrFilter()
        var ref_events = NostrFilter()

        let thread_id = original_event.thread_id()

        ref_events.referenced_ids = [thread_id, original_event.id]
        ref_events.kinds = [.text]
        ref_events.limit = 1000
        
        event_filter.ids = [thread_id, original_event.id]
        
        meta_events.referenced_ids = [original_event.id]

        var kinds: [NostrKind] = [.zap, .text, .boost]
        if !damus_state.settings.onlyzaps_mode {
            kinds.append(.like)
        }
        meta_events.kinds = kinds
        meta_events.limit = 1000

        quote_events.kinds = [.text]
        quote_events.quotes = [original_event.id]
        quote_events.limit = 1000

        let base_filters = [event_filter, ref_events]
        let meta_filters = [meta_events, quote_events]
        
        self.listener?.cancel()
        self.listener = Task {
            Log.info("subscribing to thread %s ", for: .render, original_event.id.hex())
            for await item in damus_state.nostrNetwork.reader.subscribe(filters: base_filters + meta_filters) {
                switch item {
                case .event(let lender):
                    lender.justUseACopy({ handle_event(ev: $0) })
                case .eose:
                    guard let txn = NdbTxn(ndb: damus_state.ndb) else { return }
                    load_profiles(context: "thread", load: .from_events(Array(event_map.events)), damus_state: damus_state, txn: txn)
                }
            }
        }
    }
    
    func unsubscribe() {
        self.listener?.cancel()
        self.listener = nil
    }
    
    /// Adds an event to this thread.
    /// Normally this does not need to be called externally because it is the responsibility of this class to load the events, not the view's.
    /// However, this can be called externally for testing purposes (e.g. injecting events for testing)
    /// 
    /// - Parameters:
    ///   - ev: The event to add into the thread event map
    ///   - keypair: The user's keypair
    ///   - look_for_parent_events: Whether to search for parent events of the input event in NostrDB
    ///   - publish_changes: Whether to publish changes at the end
    func add_event(_ ev: NostrEvent, keypair: Keypair, look_for_parent_events: Bool = true, publish_changes: Bool = true) {
        if event_map.contains(id: ev.id) {
            return
        }
        
        _ = damus_state.events.upsert(ev)
        damus_state.replies.count_replies(ev, keypair: keypair)
        damus_state.events.add_replies(ev: ev, keypair: keypair)

        event_map.add(event: ev)
        
        if look_for_parent_events {
            // Add all parent events that we have on EventCache (and subsequently on NostrDB)
            // This helps ensure we include as many locally-stored notes as possible — even on poor networking conditions
            damus_state.events.parent_events(event: ev, keypair: damus_state.keypair).forEach {
                add_event(
                    $0,  // The `lookup` function in `parent_events` turns the event into an "owned" object, so we do not need to clone here
                    keypair: damus_state.keypair,
                    look_for_parent_events: false,   // We do not need deep recursion
                    publish_changes: false           // Do not publish changes multiple times
                )
            }
        }
        
        if publish_changes {
            objectWillChange.send()
        }
    }
    
    /// Handles an incoming event from a relay pool
    ///
    /// Marked as private because it is this class' responsibility to load events, not the view's. Simplify the interface
    @MainActor
    private func handle_event(ev: NostrEvent) {
        if ev.known_kind == .zap {
            process_zap_event(state: damus_state, ev: ev) { zap in
                
            }
        } else if ev.is_textlike {
            // handle thread quote reposts, we just count them instead of
            // adding them to the thread
            if let target = ev.is_quote_repost, target == self.selected_event.id {
                //let _ = self.damus_state.quote_reposts.add_event(ev, target: target)
            } else {
                self.add_event(ev, keypair: damus_state.keypair)
            }
        }
        else if ev.known_kind == .boost {
            damus_state.boosts.add_event(ev, target: original_event.id)
        }
        else if ev.known_kind == .like {
            damus_state.likes.add_event(ev, target: original_event.id)
        }
    }
    
    // MARK: External control interface
    // Control methods created for the thread view
    
    /// Change the currently selected event
    ///
    /// - Parameter event: Event to select
    func select(event: NostrEvent) {
        self.selected_event = event
        add_event(event, keypair: damus_state.keypair)
    }
}

/// A thread event map, a model that holds events, indexes them, and can efficiently answer questions about a thread.
///
/// Add events that are part of a thread to this model, and use one of its many convenience functions to get answers about the hierarchy of the thread.
///
/// This does NOT perform any event loading, networking, or storage operations. This is simply a convenient/efficient way to keep and query about a thread
struct ThreadEventMap {
    /// A map for keeping nostr events, and efficiently querying them by note id
    ///
    /// Marked as `private` because:
    /// - We want to hide this complexity from the user of this struct
    /// - It is this struct's responsibility to keep this in sync with `event_reply_index`
    private var event_map: [NoteId: NostrEvent] = [:]
    /// An index of the reply hierarchy, which allows replies to be found in O(1) efficiency
    ///
    /// ## Implementation notes
    ///
    /// Marked as `private` because:
    /// - We want to hide this complexity from the user of this struct
    /// - It is this struct's responsibility to keep this in sync with `event_map`
    ///
    /// We only store note ids to save space, as we can easily get them from `event_map`
    private var event_reply_index: [NoteId: Set<NoteId>] = [:]


    // MARK: External interface

    /// Events in the thread, in no particular order
    /// Use this when the order does not matter
    var events: Set<NostrEvent> {
        return Set(event_map.values)
    }

    /// Events in the thread, sorted chronologically. Use this when the order matters.
    /// Use `.events` when the order doesn't matter, as it is more computationally efficient.
    var sorted_events: [NostrEvent] {
        return events.sorted(by: { a, b in
            return a.created_at < b.created_at
        })
    }

    /// Add an event to this map
    /// 
    /// Efficiency: O(1)
    ///
    /// - Parameter event: The event to be added
    mutating func add(event: NostrEvent) {
        self.event_map[event.id] = event
        
        // Update our efficient reply index
        if let note_id_replied_to = event.direct_replies() {
            if event_reply_index[note_id_replied_to] == nil {
                event_reply_index[note_id_replied_to] = [event.id]
            }
            else {
                event_reply_index[note_id_replied_to]?.insert(event.id)
            }
        }
    }

    /// Whether the thread map contains a given note, referenced by ID
    ///
    /// Efficiency: O(1)
    ///
    /// - Parameter id: The ID to look for
    /// - Returns: True if it does, false otherwise
    func contains(id: NoteId) -> Bool {
        return self.event_map[id] != nil
    }
    
    /// Gets a note from the thread by its id
    ///
    /// Efficiency: O(1)
    ///
    /// - Parameter id: The note id
    /// - Returns: The note, if it exists in the thread map.
    func get(id: NoteId) -> NostrEvent? {
        return self.event_map[id]
    }

    
    /// Returns all the parent events in a thread, relative to a given event
    ///
    /// Efficiency: O(N) in the worst case
    ///
    /// - Parameter query_event: The event for which to find the parents for
    /// - Returns: An array of parent events, sorted from the highest level in the thread (The root of the thread), down to the direct parent of the query event. If query event is not found, this will return an empty array
    func parent_events(of query_event: NostrEvent) -> [NostrEvent] {
        var parents: [NostrEvent] = []
        var event = query_event
        while true {
            guard let direct_reply = event.direct_replies(),
                  let parent_event = self.get(id: direct_reply), parent_event != event
            else {
                break
            }
            
            parents.append(parent_event)
            event = parent_event
        }
        
        return parents.reversed()
    }
    
    
    /// All of the replies in a thread for a given event, including indirect replies (reply of a reply), sorted in chronological order
    ///
    /// Efficiency: O(Nlog(N)) in the worst case scenario, coming from Swift's built-in sorting algorithm "Timsort"
    ///
    /// - Parameter query_event: The event for which to find the children for
    /// - Returns: All of the direct and indirect replies for an event, sorted in chronological order. If query event is not present, this will be an empty array.
    func sorted_recursive_child_events(of query_event: NostrEvent) -> [NostrEvent] {
        let all_recursive_child_events = self.recursive_child_events(of: query_event)
        return all_recursive_child_events.sorted(by: { a, b in
            return a.created_at < b.created_at
        })
    }
    
    /// All of the replies in a thread for a given event, including indirect replies (reply of a reply), in any order
    ///
    /// Use this when the order does not matter, as it is more efficient
    ///
    /// Efficiency: O(N) in the worst case scenario.
    ///
    /// - Parameter query_event: The event for which to find the children for
    /// - Returns: All of the direct and indirect replies for an event, sorted in chronological order. If query event is not present, this will be an empty array.
    func recursive_child_events(of query_event: NostrEvent) -> Set<NostrEvent> {
        let immediate_children_ids = self.event_reply_index[query_event.id] ?? []
        var immediate_children: Set<NostrEvent> = []
        for immediate_child_id in immediate_children_ids {
            guard let immediate_child = self.event_map[immediate_child_id] else {
                // This is an internal inconsistency.
                // Crash the app in debug mode to increase awareness, but let it go in production mode (not mission critical)
                assertionFailure("Desync between `event_map` and `event_reply_index` should never happen in `ThreadEventMap`!")
                continue
            }
            immediate_children.insert(immediate_child)
        }
        
        var indirect_children: Set<NdbNote> = []
        for immediate_child in immediate_children {
            let recursive_children = self.recursive_child_events(of: immediate_child)
            indirect_children = indirect_children.union(recursive_children)
        }
        return immediate_children.union(indirect_children)
    }
}


func get_top_zap(events: EventCache, evid: NoteId) -> Zapping? {
    return events.get_cache_data(evid).zaps_model.zaps.first(where: { zap in
        !zap.request.marked_hidden
    })
}
