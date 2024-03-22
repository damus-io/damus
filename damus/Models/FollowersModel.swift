//
//  FollowersModel.swift
//  damus
//
//  Created by William Casarin on 2022-05-26.
//

import Foundation

class FollowersModel: ObservableObject {
    let damus_state: DamusState
    let target: Pubkey

    @Published var contacts: [Pubkey]? = nil
    var has_contact: Set<Pubkey> = Set()

    let sub_id: String = UUID().description
    let profiles_id: String = UUID().description
    
    var count: Int? {
        guard let contacts = self.contacts else {
            return nil
        }
        return contacts.count
    }
    
    init(damus_state: DamusState, target: Pubkey) {
        self.damus_state = damus_state
        self.target = target
    }
    
    func get_filter() -> NostrFilter {
        NostrFilter(kinds: [.contacts], pubkeys: [target])
    }
    
    func subscribe() {
        let filter = get_filter()
        let filters = [filter]
        //print_filters(relay_id: "following", filters: [filters])
        self.damus_state.pool.subscribe(sub_id: sub_id, filters: filters, handler: handle_event)
    }
    
    func unsubscribe() {
        self.damus_state.pool.unsubscribe(sub_id: sub_id)
    }
    
    func handle_contact_event(_ ev: NostrEvent) {
        if has_contact.contains(ev.pubkey) {
            return
        }
        process_contact_event(state: damus_state, ev: ev)
        contacts?.append(ev.pubkey)
        has_contact.insert(ev.pubkey)
    }

    func load_profiles<Y>(relay_id: RelayURL, txn: NdbTxn<Y>) {
        let authors = find_profiles_to_fetch_from_keys(profiles: damus_state.profiles, pks: contacts ?? [], txn: txn)
        if authors.isEmpty {
            return
        }
        
        let filter = NostrFilter(kinds: [.metadata],
                                 authors: authors)
        damus_state.pool.subscribe_to(sub_id: profiles_id, filters: [filter], to: [relay_id], handler: handle_event)
    }

    func handle_event(relay_id: RelayURL, ev: NostrConnectionEvent) {
        guard case .nostr_event(let nev) = ev else {
            return
        }
        
        switch nev {
        case .event(let sub_id, let ev):
            guard sub_id == self.sub_id || sub_id == self.profiles_id else {
                return
            }
            
            if ev.known_kind == .contacts {
                handle_contact_event(ev)
            }
        case .notice(let msg):
            print("followingmodel notice: \(msg)")
            
        case .eose(let sub_id):
            if sub_id == self.sub_id {
                guard let txn = NdbTxn(ndb: self.damus_state.ndb) else { return }
                load_profiles(relay_id: relay_id, txn: txn)
            } else if sub_id == self.profiles_id {
                damus_state.pool.unsubscribe(sub_id: profiles_id, to: [relay_id])
            }
            
        case .ok:
            break
        case .auth:
            break
        }
    }
}
