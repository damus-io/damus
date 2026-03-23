//
//  SpellDiscoveryModel.swift
//  damus
//
//  Fetches kind:777 spell events from relays for feed discovery.
//

import Foundation

@MainActor
class SpellDiscoveryModel: ObservableObject {
    let damus_state: DamusState

    @Published private(set) var spells: [DiscoveredSpell] = []
    @Published private(set) var isLoading = false

    private var fetchTask: Task<Void, Never>?
    private var seenIds = Set<NoteId>()

    init(damus_state: DamusState) {
        self.damus_state = damus_state
    }

    func load() {
        guard fetchTask == nil else { return }
        isLoading = true

        fetchTask = Task { [weak self] in
            guard let self else { return }

            var filter = NostrFilter(kinds: [.spell])
            filter.limit = 100

            let stream = damus_state.nostrNetwork.reader.advancedStream(
                filters: [filter],
                to: nil,
                streamMode: .ndbAndNetworkParallel(networkOptimization: .sinceOptimization)
            )

            for await item in stream {
                guard !Task.isCancelled else { break }

                switch item {
                case .event(let lender):
                    await lender.justUseACopy { [weak self] event in
                        guard let self else { return }
                        self.handleEvent(event)
                    }
                case .ndbEose, .eose:
                    self.isLoading = false
                case .networkEose:
                    break
                }
            }
        }
    }

    func cancel() {
        fetchTask?.cancel()
        fetchTask = nil
    }

    deinit {
        fetchTask?.cancel()
    }

    private func handleEvent(_ event: NostrEvent) {
        guard !seenIds.contains(event.id) else { return }
        seenIds.insert(event.id)

        guard let spell = SpellEvent.parse(from: event) else { return }

        let json = event_to_json(ev: event)
        let discovered = DiscoveredSpell(
            noteId: event.id,
            spell: spell,
            eventJSON: json,
            authorPubkey: event.pubkey
        )
        spells.append(discovered)
    }
}

struct DiscoveredSpell: Identifiable {
    let noteId: NoteId
    let spell: SpellEvent
    let eventJSON: String
    let authorPubkey: Pubkey

    var id: NoteId { noteId }

    var displayName: String { spell.displayName }

    func toSavedFeed() -> SavedSpellFeed {
        SavedSpellFeed(
            id: noteId.hex(),
            name: spell.displayName,
            spellEventJSON: eventJSON
        )
    }
}
