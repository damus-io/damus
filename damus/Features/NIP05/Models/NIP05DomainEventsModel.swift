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
    @Published var loading_more: Bool = false
    @Published var has_more: Bool = true
    @Published var last_loaded_count: Int = 0

    let domain: String
    var friend_filter: FriendFilter
    var filter: NostrFilter
    var loadingTask: Task<Void, Never>?
    let initial_limit: UInt32 = 200
    let limit: UInt32 = 500
    private var used_initial_page: Bool = false
    private var requesting_profiles: Set<Pubkey> = []

    init(state: DamusState, domain: String, friend_filter: FriendFilter = .friends_of_friends) {
        self.state = state
        self.domain = domain
        self.friend_filter = friend_filter
        self.events = EventHolder(on_queue: { ev in
            preload_events(state: state, events: [ev])
        })
        self.filter = NostrFilter()
    }

    @MainActor
    func subscribe(resetEvents: Bool = true) {
        print("subscribing to notes with '\(domain)' NIP-05 domain (filter: \(friend_filter.rawValue))")
        filter = NostrFilter()
        if resetEvents {
            events.reset()
        } else {
            events.flush()
        }
        used_initial_page = false
        has_more = true
        loading_more = false
        loadingTask = Task {
            await streamItems()
        }
        loading = true
        last_loaded_count = 0
    }

    func unsubscribe() {
        loadingTask?.cancel()
        loading = false
        print("unsubscribing from notes with '\(domain)' NIP-05 domain (filter: \(friend_filter.rawValue))")
    }

    @MainActor
    func set_friend_filter(_ new_filter: FriendFilter) {
        guard new_filter != self.friend_filter else { return }
        self.friend_filter = new_filter

        unsubscribe()
        // Keep current events when toggling filters; stream will refill as needed.
        subscribe(resetEvents: false)
    }

    private func matches_domain(_ pubkey: Pubkey) -> Bool {
        // Prefer validated nip05 if present; fallback to raw nip05 on profile.
        if let validated = state.profiles.is_validated(pubkey),
           validated.host.caseInsensitiveCompare(domain) == .orderedSame {
            return true
        }

        let profile_txn = state.profiles.lookup(id: pubkey)
        guard let profile = profile_txn?.unsafeUnownedValue,
              let nip05_str = profile.nip05,
              let nip05 = NIP05.parse(nip05_str) else {
            return false
        }

        return nip05.host.caseInsensitiveCompare(domain) == .orderedSame
    }

    private func validated_authors_for_domain() async -> Set<Pubkey> {
        let validated = await MainActor.run { state.profiles.nip05_pubkey }
        return Set(validated.compactMap { (nip05_str, pk) in
            guard let nip05 = NIP05.parse(nip05_str),
                  nip05.host.caseInsensitiveCompare(domain) == .orderedSame else {
                return nil
            }
            return pk
        })
    }

    private func authors_for_domain() async -> Set<Pubkey> {
        var authors = Set<Pubkey>()

        switch friend_filter {
        case .friends_of_friends:
            for pubkey in state.contacts.get_friend_of_friends_list() where matches_domain(pubkey) {
                authors.insert(pubkey)
            }
        case .all:
            let validated = await validated_authors_for_domain()
            authors.formUnion(validated)

            // Also include any friend-of-friends that match the domain even if not validated yet.
            for pubkey in state.contacts.get_friend_of_friends_list() where matches_domain(pubkey) {
                authors.insert(pubkey)
            }
        }

        return authors
    }

    private func resolve_domain_match(pubkey: Pubkey) async -> Bool {
        if matches_domain(pubkey) {
            return true
        }

        if requesting_profiles.contains(pubkey) {
            return false
        }
        requesting_profiles.insert(pubkey)

        // Try to fetch metadata quickly; bail early if the task was cancelled.
        let metaFilter = NostrFilter(kinds: [.metadata], limit: 1, authors: [pubkey])
        for await lender in state.nostrNetwork.reader.timedStream(filters: [metaFilter], timeout: .seconds(3)) {
            await lender.justUseACopy { _ in }
            if Task.isCancelled { break }
        }

        requesting_profiles.remove(pubkey)
        return matches_domain(pubkey)
    }

    func streamItems() async {
        filter.limit = used_initial_page ? self.limit : self.initial_limit
        filter.kinds = [.text, .longform, .highlight]

        let authors = await authors_for_domain()
        switch friend_filter {
        case .friends_of_friends:
            if authors.isEmpty {
                await MainActor.run {
                    self.loading = false
                    self.has_more = false
                }
                return
            }
            filter.authors = Array(authors)
        case .all:
            // WOT off: do not restrict authors so we can discover new domain users.
            filter.authors = nil
        }

        await MainActor.run {
            for pubkey in authors {
                check_nip05_validity(pubkey: pubkey, profiles: state.profiles)
            }
        }

        for await item in state.nostrNetwork.reader.advancedStream(filters: [filter]) {
            switch item {
            case .event(let lender):
                await lender.justUseACopy({ await self.add_event($0) })
            case .eose:
                DispatchQueue.main.async {
                    self.loading = false
                    self.used_initial_page = true
                    self.last_loaded_count = self.events.all_events.count
                }
                continue
            case .ndbEose, .networkEose:
                break
            }
        }
    }

    @MainActor
    func load_more() {
        guard !loading_more, has_more else { return }
        guard let oldest = events.all_events.last?.created_at else { return }

        loading_more = true
        let until = oldest > 0 ? oldest &- 1 : 0
        Task {
            await self.fetch_older(until: until)
        }
    }

    private func fetch_older(until: UInt32) async {
        var moreFilter = NostrFilter()
        moreFilter.limit = self.limit
        moreFilter.kinds = [.text, .longform, .highlight]
        moreFilter.until = until
        moreFilter.authors = friend_filter == .friends_of_friends ? filter.authors : nil

        var gotEvent = false
        for await item in state.nostrNetwork.reader.advancedStream(filters: [moreFilter]) {
            switch item {
            case .event(let lender):
                gotEvent = true
                await lender.justUseACopy({ await self.add_event($0) })
            case .eose:
                DispatchQueue.main.async {
                    self.loading_more = false
                    let newCount = self.events.all_events.count
                    if !gotEvent || newCount == self.last_loaded_count {
                        self.has_more = false
                    } else {
                        self.last_loaded_count = newCount
                    }
                }
                return
            case .ndbEose, .networkEose:
                break
            }
        }

        DispatchQueue.main.async {
            self.loading_more = false
        }
    }

    func add_event(_ ev: NostrEvent) async {
        // Ignore metadata/other kinds; timeline only cares about content notes.
        if ev.known_kind == .metadata {
            return
        }

        if !event_matches_filter(ev, filter: filter) {
            return
        }

        guard await should_show_event(state: state, ev: ev) else {
            return
        }

        await MainActor.run {
            check_nip05_validity(pubkey: ev.pubkey, profiles: state.profiles)
        }

        guard await resolve_domain_match(pubkey: ev.pubkey) else {
            return
        }

        if await self.events.insert(ev) {
            DispatchQueue.main.async {
                self.objectWillChange.send()
            }
        }
    }
}
