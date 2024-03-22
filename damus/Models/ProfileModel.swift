//
//  ProfileModel.swift
//  damus
//
//  Created by William Casarin on 2022-04-27.
//

import Foundation

class ProfileModel: ObservableObject, Equatable {
    @Published var contacts: NostrEvent? = nil
    @Published var following: Int = 0
    @Published var relays: [RelayURL: RelayInfo]? = nil
    @Published var progress: Int = 0

    private let MAX_SHARE_RELAYS = 4
    
    var events: EventHolder
    let pubkey: Pubkey
    let damus: DamusState
    
    var seen_event: Set<NoteId> = Set()
    var sub_id = UUID().description
    var prof_subid = UUID().description
    var findRelay_subid = UUID().description
    
    init(pubkey: Pubkey, damus: DamusState) {
        self.pubkey = pubkey
        self.damus = damus
        self.events = EventHolder(on_queue: { ev in
            preload_events(state: damus, events: [ev])
        })
    }
    
    func follows(pubkey: Pubkey) -> Bool {
        guard let contacts = self.contacts else {
            return false
        }

        return contacts.referenced_pubkeys.contains(pubkey)
    }
    
    func get_follow_target() -> FollowTarget {
        if let contacts = contacts {
            return .contact(contacts)
        }
        return .pubkey(pubkey)
    }
    
    static func == (lhs: ProfileModel, rhs: ProfileModel) -> Bool {
        return lhs.pubkey == rhs.pubkey
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(pubkey)
    }
    
    func unsubscribe() {
        print("unsubscribing from profile \(pubkey) with sub_id \(sub_id)")
        damus.pool.unsubscribe(sub_id: sub_id)
        damus.pool.unsubscribe(sub_id: prof_subid)
    }
    
    func subscribe() {
        var text_filter = NostrFilter(kinds: [.text, .longform])
        var profile_filter = NostrFilter(kinds: [.contacts, .metadata, .boost])
        
        profile_filter.authors = [pubkey]
        
        text_filter.authors = [pubkey]
        text_filter.limit = 500
        
        print("subscribing to profile \(pubkey) with sub_id \(sub_id)")
        //print_filters(relay_id: "profile", filters: [[text_filter], [profile_filter]])
        damus.pool.subscribe(sub_id: sub_id, filters: [text_filter], handler: handle_event)
        damus.pool.subscribe(sub_id: prof_subid, filters: [profile_filter], handler: handle_event)
    }
    
    func handle_profile_contact_event(_ ev: NostrEvent) {
        process_contact_event(state: damus, ev: ev)
        
        // only use new stuff
        if let current_ev = self.contacts {
            guard ev.created_at > current_ev.created_at else {
                return
            }
        }
        
        self.contacts = ev
        self.following = count_pubkeys(ev.tags)
        self.relays = decode_json_relays(ev.content)
    }
    
    func add_event(_ ev: NostrEvent) {
        guard ev.should_show_event else {
            return
        }

        if seen_event.contains(ev.id) {
            return
        }
        if ev.is_textlike || ev.known_kind == .boost {
            if self.events.insert(ev) {
                self.objectWillChange.send()
            }
        } else if ev.known_kind == .contacts {
            handle_profile_contact_event(ev)
        }
        seen_event.insert(ev.id)
    }

    private func handle_event(relay_id: RelayURL, ev: NostrConnectionEvent) {
        switch ev {
        case .ws_event:
            return
        case .nostr_event(let resp):
            guard resp.subid == self.sub_id || resp.subid == self.prof_subid else {
                return
            }
            switch resp {
            case .ok:
                break
            case .event(_, let ev):
                // Ensure the event public key matches this profiles public key
                // This is done to protect against a relay not properly filtering events by the pubkey
                // See https://github.com/damus-io/damus/issues/1846 for more information
                guard self.pubkey == ev.pubkey else { break }

                add_event(ev)
            case .notice:
                break
                //notify(.notice, notice)
            case .eose:
                guard let txn = NdbTxn(ndb: damus.ndb) else { return }
                if resp.subid == sub_id {
                    load_profiles(context: "profile", profiles_subid: prof_subid, relay_id: relay_id, load: .from_events(events.events), damus_state: damus, txn: txn)
                }
                progress += 1
                break
            case .auth:
                break
            }
        }
    }

    private func findRelaysHandler(relay_id: RelayURL, ev: NostrConnectionEvent) {
        if case .nostr_event(let resp) = ev, case .event(_, let event) = resp, case .contacts = event.known_kind {
            self.relays = decode_json_relays(event.content)
        }
    }
    
    func subscribeToFindRelays() {
        var profile_filter = NostrFilter(kinds: [.contacts])
        profile_filter.authors = [pubkey]
        
        damus.pool.subscribe(sub_id: findRelay_subid, filters: [profile_filter], handler: findRelaysHandler)
    }
    
    func unsubscribeFindRelays() {
        damus.pool.unsubscribe(sub_id: findRelay_subid)
    }

    func getCappedRelayStrings() -> [String] {
        return relays?.keys.prefix(MAX_SHARE_RELAYS).map { $0.absoluteString } ?? []
    }
}


func count_pubkeys(_ tags: Tags) -> Int {
    var c: Int = 0
    for tag in tags {
        if tag.count >= 2 && tag[0].matches_char("p") {
            c += 1
        }
    }
    
    return c
}
