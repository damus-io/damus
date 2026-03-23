//
//  SpellFeedModel.swift
//  damus
//
//  Manages a single spell feed subscription: resolves the spell,
//  subscribes to relays, receives events, and handles lifecycle.
//

import Foundation

/// The loading state of a spell feed.
enum SpellFeedState: Equatable {
    case idle
    case loading
    case loaded
    case error(SpellFeedError)
}

enum SpellFeedError: Error, Equatable {
    case resolutionFailed(SpellResolutionError)
    case invalidRelayURL(String)
}

/// Manages a subscription for a single resolved spell feed.
///
/// Follows the single-active subscription model: only one feed
/// is subscribed at a time. Switching feeds cancels the previous
/// subscription automatically.
@MainActor
class SpellFeedModel: ObservableObject {
    let damus_state: DamusState
    let spell: SpellEvent

    @Published private(set) var state: SpellFeedState = .idle
    @Published private(set) var events: [NostrEvent] = []

    private var subscriptionTask: Task<Void, Never>?
    private var eventHolder: EventHolder

    init(damus_state: DamusState, spell: SpellEvent) {
        self.damus_state = damus_state
        self.spell = spell
        self.eventHolder = EventHolder(on_queue: { ev in
            preload_events(state: damus_state, events: [ev])
        })
    }

    /// Start the spell feed subscription.
    /// Cancels any existing subscription first.
    func subscribe() {
        unsubscribe()

        // Build resolution context
        let contacts = Array(damus_state.contacts.get_friend_list())
        let context = SpellResolutionContext(
            userPubkey: damus_state.keypair.pubkey,
            contacts: contacts,
            now: UInt64(Date().timeIntervalSince1970)
        )

        // Resolve the spell
        let result = SpellResolver.resolve(spell, context: context)

        switch result {
        case .failure(let error):
            state = .error(.resolutionFailed(error))
            return
        case .success(let resolved):
            startSubscription(resolved)
        }
    }

    /// Cancel the current subscription.
    func unsubscribe() {
        subscriptionTask?.cancel()
        subscriptionTask = nil
    }

    /// Clear cached events, deduplication state, and reset to idle.
    func reset() {
        unsubscribe()
        eventHolder = EventHolder(on_queue: { [weak self] ev in
            guard let self else { return }
            preload_events(state: self.damus_state, events: [ev])
        })
        events = []
        state = .idle
    }

    deinit {
        subscriptionTask?.cancel()
    }

    // MARK: - Private

    private func startSubscription(_ resolved: ResolvedSpell) {
        state = .loading
        eventHolder.set_should_queue(true)

        // Query local ndb first for instant results using NdbFilter
        queryLocalNdb(resolved.ndbFilters, limit: Int(spell.limit ?? 100))

        // Convert spell relay URLs to RelayURL type
        let targetRelays: [RelayURL]? = resolved.relays.isEmpty
            ? nil
            : resolved.relays.compactMap { RelayURL($0) }

        subscriptionTask = Task { [weak self] in
            guard let self else { return }

            let stream = damus_state.nostrNetwork.reader.advancedStream(
                filters: resolved.filters,
                to: targetRelays,
                streamMode: .ndbFirst(networkOptimization: .sinceOptimization)
            )

            streamLoop: for await item in stream {
                guard !Task.isCancelled else { break streamLoop }

                switch item {
                case .event(let lender):
                    await lender.justUseACopy { [weak self] event in
                        guard let self else { return }
                        self.handleEvent(event)
                    }
                case .ndbEose:
                    self.flushAndMarkLoaded()
                case .eose:
                    self.flushAndMarkLoaded()
                    if resolved.closeOnEose {
                        break streamLoop
                    }
                case .networkEose:
                    self.flushAndMarkLoaded()
                }
            }
        }
    }

    /// Query the local nostrdb for events matching the spell's NdbFilters.
    /// Results are added to the eventHolder immediately for instant display.
    private func queryLocalNdb(_ filters: [NdbFilter], limit: Int) {
        guard let noteKeys = try? damus_state.ndb.query(filters: filters, maxResults: limit) else {
            return
        }

        for key in noteKeys {
            guard let note = try? damus_state.ndb.lookup_note_by_key_and_copy(key) else { continue }
            handleEvent(note)
        }

        if !noteKeys.isEmpty {
            flushAndMarkLoaded()
        }
    }

    private func handleEvent(_ event: NostrEvent) {
        let inserted = eventHolder.insert(event)
        if inserted && !eventHolder.should_queue {
            events = eventHolder.events
        }
    }

    private func flushAndMarkLoaded() {
        eventHolder.set_should_queue(false)
        eventHolder.flush()
        events = eventHolder.events
        if state != .loaded {
            state = .loaded
        }
    }
}
