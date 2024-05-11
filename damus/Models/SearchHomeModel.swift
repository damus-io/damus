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

    var seen_pubkey: Set<Pubkey> = Set()
    let damus_state: DamusState
    let base_subid = UUID().description
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
    
    func filter_muted() {
        events.filter { should_show_event(state: damus_state, ev: $0) }
        self.objectWillChange.send()
    }
    
    func subscribe() {
        loading = true
        let to_relays = determine_to_relays(pool: damus_state.pool, filters: damus_state.relay_filters)
        damus_state.pool.subscribe(sub_id: base_subid, filters: [get_base_filter()], handler: handle_event, to: to_relays)
    }

    func unsubscribe(to: RelayURL? = nil) {
        loading = false
        damus_state.pool.unsubscribe(sub_id: base_subid, to: to.map { [$0] })
    }

    func handle_event(relay_id: RelayURL, conn_ev: NostrConnectionEvent) {
        guard case .nostr_event(let event) = conn_ev else {
            return
        }
        
        switch event {
        case .event(let sub_id, let ev):
            guard sub_id == self.base_subid || sub_id == self.profiles_subid else {
                return
            }
            if ev.is_textlike && should_show_event(state: damus_state, ev: ev) && !ev.is_reply()
            {
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
                
                guard let txn = NdbTxn(ndb: damus_state.ndb) else { return }
                load_profiles(context: "universe", profiles_subid: profiles_subid, relay_id: relay_id, load: .from_events(events.all_events), damus_state: damus_state, txn: txn)
            }

            break
        case .auth:
            break
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

func load_profiles<Y>(context: String, profiles_subid: String, relay_id: RelayURL, load: PubkeysToLoad, damus_state: DamusState, txn: NdbTxn<Y>) {
    let authors = find_profiles_to_fetch(profiles: damus_state.profiles, load: load, cache: damus_state.events, txn: txn)

    guard !authors.isEmpty else {
        return
    }
    
    print("load_profiles[\(context)]: requesting \(authors.count) profiles from \(relay_id)")

    let filter = NostrFilter(kinds: [.metadata], authors: authors)

    damus_state.pool.subscribe_to(sub_id: profiles_subid, filters: [filter], to: [relay_id]) { rid, conn_ev in
        
        let now = UInt64(Date.now.timeIntervalSince1970)
        switch conn_ev {
        case .ws_event:
            break
        case .nostr_event(let ev):
            guard ev.subid == profiles_subid, rid == relay_id else { return }

            switch ev {
            case .event(_, let ev):
                if ev.known_kind == .metadata {
                    damus_state.ndb.write_profile_last_fetched(pubkey: ev.pubkey, fetched_at: now)
                }
            case .eose:
                print("load_profiles[\(context)]: done loading \(authors.count) profiles from \(relay_id)")
                damus_state.pool.unsubscribe(sub_id: profiles_subid, to: [relay_id])
            case .ok:
                break
            case .notice:
                break
            case .auth:
                break
            }
        }


    }
}

