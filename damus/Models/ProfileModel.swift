//
//  ProfileModel.swift
//  damus
//
//  Created by William Casarin on 2022-04-27.
//

import Foundation

class ProfileModel: ObservableObject {
    @Published var events: [NostrEvent] = []
    @Published var contacts: NostrEvent? = nil
    @Published var following: Int = 0
    
    let pubkey: String
    let damus: DamusState
    
    var seen_event: Set<String> = Set()
    var sub_id = UUID().description
    
    func get_follow_target() -> FollowTarget {
        if let contacts = contacts {
            return .contact(contacts)
        }
        return .pubkey(pubkey)
    }
    
    init(pubkey: String, damus: DamusState) {
        self.pubkey = pubkey
        self.damus = damus
    }
    
    func unsubscribe() {
        print("unsubscribing from profile \(pubkey) with sub_id \(sub_id)")
        damus.pool.unsubscribe(sub_id: sub_id)
    }
    
    func subscribe() {
        let kinds: [Int] = [
            NostrKind.text.rawValue,
            NostrKind.delete.rawValue,
            NostrKind.contacts.rawValue,
            NostrKind.metadata.rawValue,
            NostrKind.boost.rawValue
        ]
        
        var filter = NostrFilter.filter_authors([pubkey])
        filter.kinds = kinds
        filter.limit = 1000
        
        print("subscribing to profile \(pubkey) with sub_id \(sub_id)")
        damus.pool.subscribe(sub_id: sub_id, filters: [filter], handler: handle_event)
    }
    
    func handle_profile_contact_event(_ ev: NostrEvent) {
        self.contacts = ev
        self.following = count_pubkeys(ev.tags)
    }
    
    func add_event(_ ev: NostrEvent) {
        if seen_event.contains(ev.id) {
            return
        }
        if ev.known_kind == .text {
            let _ = insert_uniq_sorted_event(events: &self.events, new_ev: ev, cmp: { $0.created_at > $1.created_at})
        } else if ev.known_kind == .contacts {
            handle_profile_contact_event(ev)
        }
        seen_event.insert(ev.id)
    }
    
    private func handle_event(relay_id: String, ev: NostrConnectionEvent) {
        switch ev {
        case .ws_event:
            return
        case .nostr_event(let resp):
            switch resp {
            case .event(let sid, let ev):
                if sid != self.sub_id {
                    return
                }
                add_event(ev)
            case .notice(let notice):
                notify(.notice, notice)
            }
        }
    }
}


func count_pubkeys(_ tags: [[String]]) -> Int {
    var c: Int = 0
    for tag in tags {
        if tag.count >= 2 && tag[0] == "p" {
            c += 1
        }
    }
    
    return c
}
