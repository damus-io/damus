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

    nonisolated private func resolve_domain_match(pubkey: Pubkey) async -> Bool {
        // Quick check if already matches
        let initialMatch = await MainActor.run { matches_domain(pubkey) }
        if initialMatch {
            return true
        }

        // Check if we're already requesting this profile (race condition protection)
        let alreadyRequesting = await MainActor.run { requesting_profiles.contains(pubkey) }
        if alreadyRequesting {
            return false
        }
        await MainActor.run { _ = requesting_profiles.insert(pubkey) }

        // Try to fetch metadata quickly; bail early if the task was cancelled.
        let metaFilter = NostrFilter(kinds: [.metadata], limit: 1, authors: [pubkey])
        let (state, _) = await MainActor.run { (self.state, ()) }
        for await lender in state.nostrNetwork.reader.timedStream(filters: [metaFilter], timeout: .seconds(3)) {
            await lender.justUseACopy { _ in }
            if Task.isCancelled { break }
        }

        // Cleanup synchronously on MainActor before returning
        return await MainActor.run {
            requesting_profiles.remove(pubkey)
            return matches_domain(pubkey)
        }
    }

    func streamItems() async {
        filter.limit = used_initial_page ? self.limit : self.initial_limit
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
            check_nip05_validity(pubkey: pubkey, profiles: state.profiles)
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
        // Early returns for events we don't want to display

        // Skip metadata events - we only show text content
        guard ev.known_kind != .metadata else { return }

        // Skip events that don't match our filter criteria
        guard event_matches_filter(ev, filter: filter) else { return }

        // Skip events filtered by content rules (muted, NSFW, etc)
        guard await should_show_event(state: state, ev: ev) else { return }

        // Validate the NIP-05 for this author
        check_nip05_validity(pubkey: ev.pubkey, profiles: state.profiles)

        // Note: We don't check domain match here because we pre-filtered authors
        // All events in this stream are from pubkeys with matching NIP-05 domain

        if await self.events.insert(ev) {
            self.objectWillChange.send()
        }
    }
}
