//
//  NIP05DomainEventsModel.swift
//  damus
//
//  Created by Terry Yiu on 4/11/25.
//

import FaviconFinder
import Foundation

@MainActor
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
    /// When set, the relay query includes `since` so the full time window is fetched.
    /// Used by grouped mode to ensure complete event counts.
    private var since: UInt32? = nil

    init(state: DamusState, domain: String, friend_filter: FriendFilter = .friends_of_friends) {
        self.state = state
        self.domain = domain
        self.friend_filter = friend_filter
        self.events = EventHolder(on_queue: { ev in
            preload_events(state: state, events: [ev])
        })
        self.filter = NostrFilter()
    }

    /// - Parameter since: Optional lower-bound timestamp for relay queries.
    ///   When set, the relay returns all events after this time (used by grouped mode
    ///   to ensure the full time window is fetched, not just the most recent N events).
    func subscribe(resetEvents: Bool = true, since: UInt32? = nil) {
        print("subscribing to notes with '\(domain)' NIP-05 domain (filter: \(friend_filter.rawValue), since: \(since.map(String.init) ?? "nil"))")
        self.since = since
        filter = NostrFilter()
        if resetEvents {
            events.reset()
        } else {
            events.flush()
        }
        used_initial_page = false
        has_more = true
        loading_more = false
        loadingTask?.cancel()
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

    func set_friend_filter(_ new_filter: FriendFilter) {
        guard new_filter != self.friend_filter else { return }
        self.friend_filter = new_filter

        unsubscribe()
        // Keep current events and time window when toggling filters.
        subscribe(resetEvents: false, since: self.since)
    }

    private func matches_domain(_ pubkey: Pubkey) -> Bool {
        NIP05DomainHelpers.matches_domain(pubkey, domain: domain, profiles: state.profiles)
    }

    func streamItems() async {
        // When `since` is set (grouped mode), the time window bounds the result set
        // so we can use a higher limit. Without `since`, use the normal paging limits.
        if let since {
            filter.since = since
            filter.limit = 5000
        } else {
            filter.limit = used_initial_page ? self.limit : self.initial_limit
        }
        filter.kinds = [.text, .longform, .highlight]

        // Get authors with matching NIP-05 domain
        // In WOT mode: filters to friends-of-friends
        // In discovery mode: scans all cached profiles in nostrdb
        let authors = await NIP05DomainHelpers.authors_for_domain(
            domain: domain,
            friend_filter: friend_filter,
            contacts: state.contacts,
            profiles: state.profiles,
            ndb: state.ndb
        )

        // Early return if no authors found - prevents empty queries
        guard !authors.isEmpty else {
            self.loading = false
            self.has_more = false
            return
        }

        // Query events only from authors with matching domain
        // This is much more efficient than streaming all events and filtering each one
        filter.authors = Array(authors)

        for pubkey in authors {
            check_nip05_validity(pubkey: pubkey, damus_state: state)
        }

        for await item in state.nostrNetwork.reader.advancedStream(filters: [filter]) {
            switch item {
            case .event(let lender):
                await lender.justUseACopy({ await self.add_event($0) })
            case .eose:
                self.loading = false
                self.used_initial_page = true
                self.last_loaded_count = self.events.all_events.count
                continue
            case .ndbEose, .networkEose:
                break
            }
        }
    }

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
        moreFilter.authors = filter.authors

        var gotEvent = false
        for await item in state.nostrNetwork.reader.advancedStream(filters: [moreFilter]) {
            switch item {
            case .event(let lender):
                gotEvent = true
                await lender.justUseACopy({ await self.add_event($0) })
            case .eose:
                self.loading_more = false
                let newCount = self.events.all_events.count
                if !gotEvent || newCount == self.last_loaded_count {
                    self.has_more = false
                } else {
                    self.last_loaded_count = newCount
                }
                return
            case .ndbEose, .networkEose:
                break
            }
        }

        self.loading_more = false
        self.has_more = false
    }

    func add_event(_ ev: NostrEvent) async {
        // Early returns for events we don't want to display

        // Skip metadata events - we only show text content
        guard ev.known_kind != .metadata else { return }

        // Skip events that don't match our filter criteria
        guard event_matches_filter(ev, filter: filter) else { return }

        // Skip events filtered by content rules (muted, NSFW, etc)
        guard await should_show_event(state: state, ev: ev) else { return }

        // Validate the NIP-05 for this author
        check_nip05_validity(pubkey: ev.pubkey, damus_state: state)

        // Note: We don't check domain match here because we pre-filtered authors
        // All events in this stream are from pubkeys with matching NIP-05 domain

        if await self.events.insert(ev) {
            self.objectWillChange.send()
        }
    }
}
