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
    var loadingTask: Task<Void, Never>?
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
        print("subscribing to notes from friends of friends with '\(domain)' NIP-05 domain")
        loadingTask = Task {
            await streamItems()
        }
        loading = true
    }

    func unsubscribe() {
        loadingTask?.cancel()
        loading = false
        print("unsubscribing from notes from friends of friends with '\(domain)' NIP-05 domain")
    }
    
    func streamItems() async {
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

        
        for await item in state.nostrNetwork.reader.subscribe(filters: [filter]) {
            switch item {
            case .event(let lender):
                await lender.justUseACopy({ await self.add_event($0) })
            case .eose:
                guard let txn = NdbTxn(ndb: state.ndb) else { return }
                load_profiles(context: "search", load: .from_events(self.events.all_events), damus_state: state, txn: txn)
                DispatchQueue.main.async { self.loading = false }
                continue
            }
        }
    }

    func add_event(_ ev: NostrEvent) async {
        if !event_matches_filter(ev, filter: filter) {
            return
        }

        guard await should_show_event(state: state, ev: ev) else {
            return
        }

        if await self.events.insert(ev) {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
}
