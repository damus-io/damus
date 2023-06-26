//
//  SearchHomeModel.swift
//  damus
//
//  Created by William Casarin on 2022-06-06.
//

import Foundation


/// The data model for the SearchHome view, typically something global-like
class SearchHomeModel: ObservableObject {
    var events: EventHolder
    @Published var loading: Bool = false

    var seen_pubkey: Set<String> = Set()
    let damus_state: DamusState
    let base_subid = UUID().description
    let profiles_subid = UUID().description
    let limit: UInt32 = 250
    //let multiple_events_per_pubkey: Bool = false
    
    init(damus_state: DamusState) {
        self.damus_state = damus_state
        self.events = EventHolder(on_queue: { ev in
            preload_events(state: damus_state, events: [ev])
        })
    }
    
    func get_base_filter() -> NostrFilter {
        var filter = NostrFilter(kinds: [.text, .chat])
        filter.limit = self.limit
        filter.until = Int64(Date.now.timeIntervalSince1970)
        return filter
    }
    
    func filter_muted() {
        events.filter { should_show_event(contacts: damus_state.contacts, ev: $0) }
        self.objectWillChange.send()
    }
    
    func subscribe() {
        loading = true
        let to_relays = determine_to_relays(pool: damus_state.pool, filters: damus_state.relay_filters)
        damus_state.pool.subscribe(sub_id: base_subid, filters: [get_base_filter()], handler: handle_event, to: to_relays)
    }

    func unsubscribe(to: String? = nil) {
        loading = false
        damus_state.pool.unsubscribe(sub_id: base_subid, to: to.map { [$0] })
    }
    
    func handle_event(relay_id: String, conn_ev: NostrConnectionEvent) {
        guard case .nostr_event(let event) = conn_ev else {
            return
        }
        
        switch event {
        case .event(let sub_id, let ev):
            guard sub_id == self.base_subid || sub_id == self.profiles_subid else {
                return
            }
            if ev.is_textlike && should_show_event(contacts: damus_state.contacts, ev: ev) && !ev.is_reply(nil) {
                if !damus_state.settings.multiple_events_per_pubkey && seen_pubkey.contains(ev.pubkey) {
                    return
                }
                seen_pubkey.insert(ev.pubkey)
                
                if self.events.insert(ev) {
                    self.objectWillChange.send()
                }
            }
        case .notice(let msg):
            print("search home notice: \(msg)")
        case .ok:
            break
        case .eose(let sub_id):
            loading = false
            
            if sub_id == self.base_subid {
                // Make sure we unsubscribe after we've fetched the global events
                // global events are not realtime
                unsubscribe(to: relay_id)
                
                load_profiles(profiles_subid: profiles_subid, relay_id: relay_id, load: .from_events(events.all_events), damus_state: damus_state)
            }
            
            
            break
        }
    }
}

func find_profiles_to_fetch(profiles: Profiles, load: PubkeysToLoad, cache: EventCache) -> [String] {
    switch load {
    case .from_events(let events):
        return find_profiles_to_fetch_from_events(profiles: profiles, events: events, cache: cache)
    case .from_keys(let pks):
        return find_profiles_to_fetch_from_keys(profiles: profiles, pks: pks)
    }
}

func find_profiles_to_fetch_from_keys(profiles: Profiles, pks: [String]) -> [String] {
    Array(Set(pks.filter { pk in !profiles.has_fresh_profile(id: pk) }))
}

func find_profiles_to_fetch_from_events(profiles: Profiles, events: [NostrEvent], cache: EventCache) -> [String] {
    var pubkeys = Set<String>()
    
    for ev in events {
        // lookup profiles from boosted events
        if ev.known_kind == .boost, let bev = ev.get_inner_event(cache: cache), !profiles.has_fresh_profile(id: bev.pubkey) {
            pubkeys.insert(bev.pubkey)
        }
        
        if !profiles.has_fresh_profile(id: ev.pubkey) {
            pubkeys.insert(ev.pubkey)
        }
    }
    
    return Array(pubkeys)
}

enum PubkeysToLoad {
    case from_events([NostrEvent])
    case from_keys([String])
}

func load_profiles(profiles_subid: String, relay_id: String, load: PubkeysToLoad, damus_state: DamusState) {
    let authors = find_profiles_to_fetch(profiles: damus_state.profiles, load: load, cache: damus_state.events)
    guard !authors.isEmpty else {
        return
    }
    
    print("loading \(authors.count) profiles from \(relay_id)")
    
    let filter = NostrFilter(kinds: [.metadata],
                             authors: authors)
    
    damus_state.pool.subscribe_to(sub_id: profiles_subid, filters: [filter], to: [relay_id]) { sub_id, conn_ev in
        let (sid, done) = handle_subid_event(pool: damus_state.pool, relay_id: relay_id, ev: conn_ev) { sub_id, ev in
            guard sub_id == profiles_subid else {
                return
            }
            
            if ev.known_kind == .metadata {
                process_metadata_event(events: damus_state.events, our_pubkey: damus_state.pubkey, profiles: damus_state.profiles, ev: ev)
            }
            
        }
        
        guard done && sid == profiles_subid else {
            return
        }
            
        print("done loading \(authors.count) profiles from \(relay_id)")
        damus_state.pool.unsubscribe(sub_id: profiles_subid, to: [relay_id])
    }
}

