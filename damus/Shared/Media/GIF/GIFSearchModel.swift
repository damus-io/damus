//
//  GIFSearchModel.swift
//  damus
//
//  Discovers GIFs on the nostr network via kind 1063 (NIP-94) events.
//

import Foundation

/// A single discovered GIF with its metadata.
struct DiscoveredGIF: Identifiable, Equatable {
    let id: NoteId
    let url: URL
    let thumbURL: URL?
    let dim: ImageMetaDim?
    let alt: String?
    let pubkey: Pubkey
    let createdAt: UInt32
}

/// Queries relays for kind 1063 events with mime type "image/gif".
@MainActor
class GIFSearchModel: ObservableObject {
    @Published var gifs: [DiscoveredGIF] = []
    @Published var loading: Bool = false

    private let damus_state: DamusState
    private var searchTask: Task<Void, any Error>?
    private var seenIDs = Set<NoteId>()

    init(damus_state: DamusState) {
        self.damus_state = damus_state
    }

    func load(limit: UInt32 = 200) {
        searchTask?.cancel()
        seenIDs.removeAll()
        gifs.removeAll()

        searchTask = Task {
            self.loading = true

            var filter = NostrFilter(kinds: [.file_metadata])
            filter.mime_types = ["image/gif"]
            filter.limit = limit
            filter.until = UInt32(Date.now.timeIntervalSince1970)

            let to_relays = await damus_state.nostrNetwork.ourRelayDescriptors
                .map { $0.url }
                .filter { !damus_state.relay_filters.is_filtered(timeline: .search, relay_id: $0) }

            for await item in damus_state.nostrNetwork.reader.advancedStream(
                filters: [filter],
                to: to_relays
            ) {
                switch item {
                case .event(let lender):
                    await lender.justUseACopy({ ev in
                        await self.handleEvent(ev)
                    })
                case .eose:
                    break
                case .ndbEose:
                    self.loading = false
                case .networkEose:
                    break
                }
            }
        }
    }

    func search(query: String) {
        guard !query.isEmpty else {
            load()
            return
        }
        searchTask?.cancel()
        seenIDs.removeAll()
        gifs.removeAll()

        searchTask = Task {
            self.loading = true

            var filter = NostrFilter(kinds: [.file_metadata])
            filter.mime_types = ["image/gif"]
            filter.limit = 100
            filter.until = UInt32(Date.now.timeIntervalSince1970)
            filter.hashtag = [query.lowercased()]

            let to_relays = await damus_state.nostrNetwork.ourRelayDescriptors
                .map { $0.url }
                .filter { !damus_state.relay_filters.is_filtered(timeline: .search, relay_id: $0) }

            for await item in damus_state.nostrNetwork.reader.advancedStream(
                filters: [filter],
                to: to_relays
            ) {
                switch item {
                case .event(let lender):
                    await lender.justUseACopy({ ev in
                        await self.handleEvent(ev)
                    })
                case .eose:
                    break
                case .ndbEose:
                    self.loading = false
                case .networkEose:
                    break
                }
            }
        }
    }

    func cancel() {
        searchTask?.cancel()
        searchTask = nil
        loading = false
    }

    @MainActor
    private func handleEvent(_ ev: NostrEvent) {
        guard ev.known_kind == .file_metadata else { return }
        guard !seenIDs.contains(ev.id) else { return }

        guard let meta = decode_file_metadata(from: ev), meta.isGIF else {
            return
        }

        seenIDs.insert(ev.id)
        let gif = DiscoveredGIF(
            id: ev.id,
            url: meta.url,
            thumbURL: meta.thumbURL ?? meta.imageURL,
            dim: meta.dim,
            alt: meta.alt ?? meta.summary,
            pubkey: ev.pubkey,
            createdAt: ev.created_at
        )
        gifs.append(gif)
    }
}
