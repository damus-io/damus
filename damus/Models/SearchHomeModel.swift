//
//  SearchHomeModel.swift
//  damus
//
//  Created by William Casarin on 2022-06-06.
//

import Foundation


/// The data model for the SearchHome view, typically something global-like
class SearchHomeModel: ObservableObject {
    @Published var events: [NostrEvent] = []
    @Published var loading: Bool = false

    var seen_pubkey: Set<String> = Set()
    let damus_state: DamusState
    let base_subid = UUID().description
    let profiles_subid = UUID().description
    let limit: UInt32 = 250
    
    init(damus_state: DamusState) {
        self.damus_state = damus_state
    }
    
    func get_base_filter() -> NostrFilter {
        var filter = NostrFilter.filter_kinds([1, 42])
        filter.limit = self.limit
        filter.until = Int64(Date.now.timeIntervalSince1970)
        return filter
    }
    
    func subscribe() {
        loading = true
        damus_state.pool.subscribe(sub_id: base_subid, filters: [get_base_filter()], handler: handle_event)
    }

    func unsubscribe() {
        loading = false
        damus_state.pool.unsubscribe(sub_id: base_subid)
    }
    
    func load_profiles(relay_id: String) {
        var filter = NostrFilter.filter_profiles
        let authors = find_profiles_to_fetch(profiles: damus_state.profiles, events: events)
        filter.authors = authors
        
        if !authors.isEmpty {
            damus_state.pool.subscribe(sub_id: profiles_subid, filters: [filter], handler: handle_event)
        }
    }
    
    func handle_event(relay_id: String, conn_ev: NostrConnectionEvent) {
        switch conn_ev {
        case .ws_event:
            break
        case .nostr_event(let event):
            switch event {
            case .event(let sub_id, let ev):
                guard sub_id == self.base_subid || sub_id == self.profiles_subid else {
                    return
                }
                if ev.is_textlike && ev.should_show_event {
                    if seen_pubkey.contains(ev.pubkey) {
                        return
                    }
                    seen_pubkey.insert(ev.pubkey)
                    let _ = insert_uniq_sorted_event(events: &events, new_ev: ev) {
                        $0.created_at > $1.created_at
                    }
                } else if ev.known_kind == .metadata {
                    process_metadata_event(image_cache: damus_state.image_cache, profiles: damus_state.profiles, ev: ev)
                }
            case .notice(let msg):
                print("search home notice: \(msg)")
            case .eose(let sub_id):
                loading = false
                
                if sub_id == self.base_subid {
                    load_profiles(relay_id: relay_id)
                } else if sub_id == self.profiles_subid {
                    damus_state.pool.unsubscribe(sub_id: self.profiles_subid)
                }
                
                break
            }
        }
    }
}

func find_profiles_to_fetch_pk(profiles: Profiles, event_pubkeys: [String]) -> [String] {
    var pubkeys = Set<String>()
    
    for pk in event_pubkeys {
        if profiles.lookup(id: pk) != nil {
            continue
        }
        
        pubkeys.insert(pk)
    }
    
    return Array(pubkeys)
}
    
func find_profiles_to_fetch(profiles: Profiles, events: [NostrEvent]) -> [String] {
    var pubkeys = Set<String>()
    
    for ev in events {
        if profiles.lookup(id: ev.pubkey) != nil {
            continue
        }
        
        pubkeys.insert(ev.pubkey)
    }
    
    return Array(pubkeys)
}
