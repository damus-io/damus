//
//  FollowersModel.swift
//  damus
//
//  Created by William Casarin on 2022-05-26.
//

import Foundation

class FollowersModel: ObservableObject {
    let damus_state: DamusState
    let target: String
    var needs_sub: Bool = true
    
    @Published var contacts: [String] = []
    var has_contact: Set<String> = Set()
    
    let sub_id: String = UUID().description
    let profiles_id: String = UUID().description
    
    init(damus_state: DamusState, target: String) {
        self.damus_state = damus_state
        self.target = target
    }
    
    func get_filter() -> NostrFilter {
        var filter = NostrFilter.filter_contacts
        filter.pubkeys = [target]
        return filter
    }
    
    func subscribe() {
        let filter = get_filter()
        let filters = [filter]
        print_filters(relay_id: "following", filters: [filters])
        self.damus_state.pool.subscribe(sub_id: sub_id, filters: filters, handler: handle_event)
    }
    
    func unsubscribe() {
        self.damus_state.pool.unsubscribe(sub_id: sub_id)
    }
    
    func handle_contact_event(_ ev: NostrEvent) {
        if has_contact.contains(ev.pubkey) {
            return
        }
        process_contact_event(
            pool: damus_state.pool,
            contacts: damus_state.contacts,
            pubkey: damus_state.pubkey, ev: ev
        )
        contacts.append(ev.pubkey)
        has_contact.insert(ev.pubkey)
    }
    
    func load_profiles(relay_id: String) {
        var filter = NostrFilter.filter_profiles
        let authors = find_profiles_to_fetch_pk(profiles: damus_state.profiles, event_pubkeys: contacts)
        if authors.isEmpty {
            return
        }
        
        filter.authors = authors
        
        damus_state.pool.subscribe_to(sub_id: profiles_id, filters: [filter], to: [relay_id], handler: handle_event)
    }
    
    func handle_event(relay_id: String, ev: NostrConnectionEvent) {
        switch ev {
        case .ws_event:
            break
        case .nostr_event(let nev):
            switch nev {
            case .event(let sub_id, let ev):
                guard sub_id == self.sub_id || sub_id == self.profiles_id else {
                    return
                }
                
                if ev.known_kind == .contacts {
                    handle_contact_event(ev)
                } else if ev.known_kind == .metadata {
                    process_metadata_event(image_cache: damus_state.image_cache, profiles: damus_state.profiles, ev: ev)
                }
                
            case .notice(let msg):
                print("followingmodel notice: \(msg)")
                
            case .eose(let sub_id):
                if sub_id == self.sub_id {
                    load_profiles(relay_id: relay_id)
                } else if sub_id == self.profiles_id {
                    damus_state.pool.unsubscribe(sub_id: profiles_id, to: [relay_id])
                }
            }
        }
    }
}
