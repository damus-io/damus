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
    @Published var relay_list: NIP65.RelayList? = nil
    @Published var legacy_relay_list: [RelayURL: LegacyKind3RelayRWConfiguration]? = nil
    @Published var progress: Int = 0
    var relay_urls: [RelayURL]? {
        if let relay_list {
            return relay_list.relays.values.map({ $0.url })
        }
        if let legacy_relay_list {
            return Array(legacy_relay_list.keys)
        }
        return nil
    }

    private let MAX_SHARE_RELAYS = 4
    
    var events: EventHolder
    let pubkey: Pubkey
    let damus: DamusState
    
    var seen_event: Set<NoteId> = Set()
    var sub_id = UUID().description
    var prof_subid = UUID().description
    var conversations_subid = UUID().description
    var findRelay_subid = UUID().description
    var conversation_events: Set<NoteId> = Set()

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
        damus.nostrNetwork.pool.unsubscribe(sub_id: sub_id)
        damus.nostrNetwork.pool.unsubscribe(sub_id: prof_subid)
        if pubkey != damus.pubkey {
            damus.nostrNetwork.pool.unsubscribe(sub_id: conversations_subid)
        }
    }

    func subscribe() {
        var text_filter = NostrFilter(kinds: [.text, .longform, .highlight])
        var profile_filter = NostrFilter(kinds: [.contacts, .metadata, .boost])
        var relay_list_filter = NostrFilter(kinds: [.relay_list], authors: [pubkey])

        profile_filter.authors = [pubkey]
        
        text_filter.authors = [pubkey]
        text_filter.limit = 500

        print("subscribing to textlike events from profile \(pubkey) with sub_id \(sub_id)")
        //print_filters(relay_id: "profile", filters: [[text_filter], [profile_filter]])
        damus.nostrNetwork.pool.subscribe(sub_id: sub_id, filters: [text_filter], handler: handle_event)
        damus.nostrNetwork.pool.subscribe(sub_id: prof_subid, filters: [profile_filter, relay_list_filter], handler: handle_event)

        subscribe_to_conversations()
    }

    private func subscribe_to_conversations() {
        // Only subscribe to conversation events if the profile is not us.
        guard pubkey != damus.pubkey else {
            return
        }

        let conversation_kinds: [NostrKind] = [.text, .longform, .highlight]
        let limit: UInt32 = 500
        let conversations_filter_them = NostrFilter(kinds: conversation_kinds, pubkeys: [damus.pubkey], limit: limit, authors: [pubkey])
        let conversations_filter_us = NostrFilter(kinds: conversation_kinds, pubkeys: [pubkey], limit: limit, authors: [damus.pubkey])
        print("subscribing to conversation events from and to profile \(pubkey) with sub_id \(conversations_subid)")
        damus.nostrNetwork.pool.subscribe(sub_id: conversations_subid, filters: [conversations_filter_them, conversations_filter_us], handler: handle_event)
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
        self.legacy_relay_list = decode_json_relays(ev.content)
    }

    private func add_event(_ ev: NostrEvent) {
        if ev.is_textlike || ev.known_kind == .boost {
            if self.events.insert(ev) {
                self.objectWillChange.send()
            }
        } else if ev.known_kind == .contacts {
            handle_profile_contact_event(ev)
        }
        else if ev.known_kind == .relay_list {
            self.relay_list = try? NIP65.RelayList(event: ev) // Whether another user's list is malformatted is something beyond our control. Probably best to suppress errors
        }
        seen_event.insert(ev.id)
    }

    // Ensure the event public key matches the public key(s) we are querying.
    // This is done to protect against a relay not properly filtering events by the pubkey
    // See https://github.com/damus-io/damus/issues/1846 for more information
    private func relay_filtered_correctly(_ ev: NostrEvent, subid: String?) -> Bool {
        if subid == self.conversations_subid {
            switch ev.pubkey {
            case self.pubkey:
                return ev.referenced_pubkeys.contains(damus.pubkey)
            case damus.pubkey:
                return ev.referenced_pubkeys.contains(self.pubkey)
            default:
                return false
            }
        }

        return self.pubkey == ev.pubkey
    }

    private func handle_event(relay_id: RelayURL, ev: NostrConnectionEvent) {
        switch ev {
        case .ws_event:
            return
        case .nostr_event(let resp):
            guard resp.subid == self.sub_id || resp.subid == self.prof_subid || resp.subid == self.conversations_subid else {
                return
            }
            switch resp {
            case .ok:
                break
            case .event(_, let ev):
                guard ev.should_show_event else {
                    break
                }

                if !seen_event.contains(ev.id) {
                    guard relay_filtered_correctly(ev, subid: resp.subid) else {
                        break
                    }

                    add_event(ev)

                    if resp.subid == self.conversations_subid {
                        conversation_events.insert(ev.id)
                    }
                } else if resp.subid == self.conversations_subid && !conversation_events.contains(ev.id) {
                    guard relay_filtered_correctly(ev, subid: resp.subid) else {
                        break
                    }

                    conversation_events.insert(ev.id)
                }
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
            self.legacy_relay_list = decode_json_relays(event.content)
        }
    }
    
    func subscribeToFindRelays() {
        var profile_filter = NostrFilter(kinds: [.contacts])
        profile_filter.authors = [pubkey]
        
        damus.nostrNetwork.pool.subscribe(sub_id: findRelay_subid, filters: [profile_filter], handler: findRelaysHandler)
    }
    
    func unsubscribeFindRelays() {
        damus.nostrNetwork.pool.unsubscribe(sub_id: findRelay_subid)
    }

    func getCappedRelays() -> [RelayURL] {
        return relay_list?.relays.keys.prefix(MAX_SHARE_RELAYS).map { $0 } ?? []
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
