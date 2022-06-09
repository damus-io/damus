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
    var prof_subid = UUID().description
    
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
        damus.pool.unsubscribe(sub_id: prof_subid)
    }
    
    func subscribe() {
        var text_filter = NostrFilter.filter_kinds([
            NostrKind.text.rawValue
        ])
        
        var profile_filter = NostrFilter.filter_kinds([
            NostrKind.contacts.rawValue,
            NostrKind.metadata.rawValue,
            NostrKind.boost.rawValue,
        ])
        
        profile_filter.authors = [pubkey]
        
        text_filter.authors = [pubkey]
        text_filter.limit = 1000
        
        print("subscribing to profile \(pubkey) with sub_id \(sub_id)")
        print_filters(relay_id: "profile", filters: [[text_filter], [profile_filter]])
        damus.pool.subscribe(sub_id: sub_id, filters: [text_filter], handler: handle_event)
        damus.pool.subscribe(sub_id: prof_subid, filters: [profile_filter], handler: handle_event)
    }
    
    func handle_profile_contact_event(_ ev: NostrEvent) {
        self.contacts = ev
        self.following = count_pubkeys(ev.tags)
        if damus.contacts.is_friend(ev.pubkey) {
            self.damus.contacts.add_friend_contact(ev)
        }
    }
    
    func add_event(_ ev: NostrEvent) {
        if seen_event.contains(ev.id) {
            return
        }
        if ev.known_kind == .text || ev.known_kind == .boost {
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
                if sid != self.sub_id && sid != self.prof_subid {
                    return
                }
                add_event(ev)
            case .notice(let notice):
                notify(.notice, notice)
            case .eose:
                break
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
