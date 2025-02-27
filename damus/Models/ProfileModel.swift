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
    @Published var relays: [RelayURL: LegacyKind3RelayRWConfiguration]? = nil
    @Published var progress: Int = 0

    private let MAX_SHARE_RELAYS = 4
    
    var events: EventHolder
    let pubkey: Pubkey
    let damus: DamusState
    
    var seen_event: Set<NoteId> = Set()
    
    var findRelaysListener: Task<Void, Never>? = nil
    var listener: Task<Void, Never>? = nil
    var profileListener: Task<Void, Never>? = nil
    
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

    func subscribe() {
        print("subscribing to profile \(pubkey)")
        listener?.cancel()
        listener = Task {
            var text_filter = NostrFilter(kinds: [.text, .longform, .highlight])
            text_filter.authors = [pubkey]
            text_filter.limit = 500
            for await item in await damus.networkManager.subscribe(filters: [text_filter]) {
                switch item {
                case .event(let event): handleNostrEvent(event)
                case .eose: break
                }
            }
            guard let txn = NdbTxn(ndb: damus.ndb) else { return }
            load_profiles(context: "profile", load: .from_events(events.events), damus_state: damus, txn: txn)
            progress += 1
        }
        profileListener?.cancel()
        profileListener = Task {
            var profile_filter = NostrFilter(kinds: [.contacts, .metadata, .boost])
            profile_filter.authors = [pubkey]
            for await item in await damus.networkManager.subscribe(filters: [profile_filter]) {
                switch item {
                case .event(let event): handleNostrEvent(event)
                case .eose: break
                }
            }
            progress += 1
        }
    }
    
    func unsubscribe() {
        listener?.cancel()
        listener = nil
        profileListener?.cancel()
        profileListener = nil
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
    
    @MainActor
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
    
    private func handleNostrEvent(_ ev: NostrEvent) {
        // Ensure the event public key matches this profiles public key
        // This is done to protect against a relay not properly filtering events by the pubkey
        // See https://github.com/damus-io/damus/issues/1846 for more information
        guard self.pubkey == ev.pubkey else { return }
        Task { await add_event(ev) }
    }

    private func findRelaysHandler(relay_id: RelayURL, ev: NostrConnectionEvent) {
        if case .nostr_event(let resp) = ev, case .event(_, let event) = resp, case .contacts = event.known_kind {
            self.relays = decode_json_relays(event.content)
        }
    }
    
    func subscribeToFindRelays() {
        var profile_filter = NostrFilter(kinds: [.contacts])
        profile_filter.authors = [pubkey]
        self.findRelaysListener?.cancel()
        self.findRelaysListener = Task {
            for await item in await damus.networkManager.subscribe(filters: [profile_filter]) {
                switch item {
                case .event(let event):
                    if case .contacts = event.known_kind {
                        self.relays = decode_json_relays(event.content)
                    }
                case .eose:
                    break
                }
            }
        }
    }
    
    func unsubscribeFindRelays() {
        self.findRelaysListener?.cancel()
        self.findRelaysListener = nil
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
