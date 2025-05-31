//
//  NIP05DomainEventsModel.swift
//  damus
//
//  Created by Terry Yiu on 4/11/25.
//

import FaviconFinder
import Foundation

class NIP05DomainEventsModel: ObservableObject {
    let state: DamusState
    var events: EventHolder
    @Published var loading: Bool = false

    let domain: String
    var filter: NostrFilter
    let sub_id = UUID().description
    let profiles_subid = UUID().description
    let limit: UInt32 = 500

    init(state: DamusState, domain: String) {
        self.state = state
        self.domain = domain
        self.events = EventHolder(on_queue: { ev in
            preload_events(state: state, events: [ev])
        })
        self.filter = NostrFilter()
    }

    @MainActor func subscribe() {
        filter.limit = self.limit
        filter.kinds = [.text, .longform, .highlight]

        var authors = Set<Pubkey>()
        for pubkey in state.contacts.get_friend_of_friends_list() {
            let profile_txn = state.profiles.lookup(id: pubkey)

            guard let profile = profile_txn?.unsafeUnownedValue,
                  let nip05_str = profile.nip05,
                  let nip05 = NIP05.parse(nip05_str),
                  nip05.host.caseInsensitiveCompare(domain) == .orderedSame else {
                continue
            }

            authors.insert(pubkey)
        }
        if authors.isEmpty {
            return
        }
        filter.authors = Array(authors)

        print("subscribing to notes from friends of friends with '\(domain)' NIP-05 domain with sub_id \(sub_id)")
        state.nostrNetwork.pool.register_handler(sub_id: sub_id, handler: handle_event)
        loading = true
        state.nostrNetwork.pool.send(.subscribe(.init(filters: [filter], sub_id: sub_id)))
    }

    func unsubscribe() {
        state.nostrNetwork.pool.unsubscribe(sub_id: sub_id)
        loading = false
        print("unsubscribing from notes from friends of friends with '\(domain)' NIP-05 domain with sub_id \(sub_id)")
    }

    func add_event(_ ev: NostrEvent) {
        if !event_matches_filter(ev, filter: filter) {
            return
        }

        guard should_show_event(state: state, ev: ev) else {
            return
        }

        if self.events.insert(ev) {
            objectWillChange.send()
        }
    }

    func handle_event(relay_id: RelayURL, ev: NostrConnectionEvent) {
        let (sub_id, done) = handle_subid_event(pool: state.nostrNetwork.pool, relay_id: relay_id, ev: ev) { sub_id, ev in
            if sub_id == self.sub_id && ev.is_textlike && ev.should_show_event {
                self.add_event(ev)
            }
        }

        guard done else {
            return
        }

        self.loading = false

        if sub_id == self.sub_id {
            guard let txn = NdbTxn(ndb: state.ndb) else { return }
            load_profiles(context: "search", profiles_subid: self.profiles_subid, relay_id: relay_id, load: .from_events(self.events.all_events), damus_state: state, txn: txn)
        }
    }
}
