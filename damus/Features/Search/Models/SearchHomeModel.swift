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

    var seen_pubkey: Set<Pubkey> = Set()
    let damus_state: DamusState
    let base_subid = UUID().description
    let follow_pack_subid = UUID().description
    let profiles_subid = UUID().description
    let limit: UInt32 = 500
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
        filter.until = UInt32(Date.now.timeIntervalSince1970)
        return filter
    }
    
    @MainActor
    func filter_muted() {
        events.filter { should_show_event(state: damus_state, ev: $0) }
        self.objectWillChange.send()
    }
    
    func load() async {
        DispatchQueue.main.async {
            self.loading = true
        }
        let to_relays = damus_state.nostrNetwork.ourRelayDescriptors
            .map { $0.url }
            .filter { !damus_state.relay_filters.is_filtered(timeline: .search, relay_id: $0) }
        outerLoop: for await item in damus_state.nostrNetwork.reader.subscribe(filters: [get_base_filter()], to: to_relays) {
            switch item {
            case .event(let borrow):
                var event: NostrEvent? = nil
                try? borrow { ev in
                    event = ev.toOwned()
                }
                guard let event else { return }
                await self.handleEvent(event)
            case .eose:
                break outerLoop
            }
        }
        DispatchQueue.main.async {
            self.loading = false
        }
        
        guard let txn = NdbTxn(ndb: damus_state.ndb) else { return }
        load_profiles(context: "universe", load: .from_events(events.all_events), damus_state: damus_state, txn: txn)
    }
    
    @MainActor
    func handleEvent(_ ev: NostrEvent) {
        if ev.is_textlike && should_show_event(state: damus_state, ev: ev) && !ev.is_reply() {
            if !damus_state.settings.multiple_events_per_pubkey && seen_pubkey.contains(ev.pubkey) {
                return
            }
            seen_pubkey.insert(ev.pubkey)
            
            if self.events.insert(ev) {
                self.objectWillChange.send()
            }
        }
    }
}

func find_profiles_to_fetch<Y>(profiles: Profiles, load: PubkeysToLoad, cache: EventCache, txn: NdbTxn<Y>) -> [Pubkey] {
    switch load {
    case .from_events(let events):
        return find_profiles_to_fetch_from_events(profiles: profiles, events: events, cache: cache, txn: txn)
    case .from_keys(let pks):
        return find_profiles_to_fetch_from_keys(profiles: profiles, pks: pks, txn: txn)
    }
}

func find_profiles_to_fetch_from_keys<Y>(profiles: Profiles, pks: [Pubkey], txn: NdbTxn<Y>) -> [Pubkey] {
    Array(Set(pks.filter { pk in !profiles.has_fresh_profile(id: pk, txn: txn) }))
}

func find_profiles_to_fetch_from_events<Y>(profiles: Profiles, events: [NostrEvent], cache: EventCache, txn: NdbTxn<Y>) -> [Pubkey] {
    var pubkeys = Set<Pubkey>()

    for ev in events {
        // lookup profiles from boosted events
        if ev.known_kind == .boost, let bev = ev.get_inner_event(cache: cache), !profiles.has_fresh_profile(id: bev.pubkey, txn: txn) {
            pubkeys.insert(bev.pubkey)
        }
        
        if !profiles.has_fresh_profile(id: ev.pubkey, txn: txn) {
            pubkeys.insert(ev.pubkey)
        }
    }
    
    return Array(pubkeys)
}

enum PubkeysToLoad {
    case from_events([NostrEvent])
    case from_keys([Pubkey])
}

func load_profiles<Y>(context: String, load: PubkeysToLoad, damus_state: DamusState, txn: NdbTxn<Y>) {
    let authors = find_profiles_to_fetch(profiles: damus_state.profiles, load: load, cache: damus_state.events, txn: txn)

    guard !authors.isEmpty else {
        return
    }
    
    Task {
        print("load_profiles[\(context)]: requesting \(authors.count) profiles from relay pool")
        let filter = NostrFilter(kinds: [.metadata], authors: authors)
        
        for await item in damus_state.nostrNetwork.reader.subscribe(filters: [filter]) {
            let now = UInt64(Date.now.timeIntervalSince1970)
            switch item {
            case .event(let borrow):
                var event: NostrEvent? = nil
                try? borrow { ev in
                    event = ev.toOwned()
                }
                guard let event else { return }
                if event.known_kind == .metadata {
                    damus_state.ndb.write_profile_last_fetched(pubkey: event.pubkey, fetched_at: now)
                }
            case .eose:
                break
            }
        }
        
        print("load_profiles[\(context)]: done loading \(authors.count) profiles from relay pool")
    }
}

