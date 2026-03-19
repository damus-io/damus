//
//  GIFSearchModel.swift
//  damus
//
//  Discovers GIFs on the nostr network via kind 1063 (NIP-94) events
//  and by scouring kind:1 notes for .gif URLs as a bootstrap mechanism.
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

/// Queries relays for GIFs via kind 1063 metadata events and kind:1 content scouring.
@MainActor
class GIFSearchModel: ObservableObject {
    @Published var gifs: [DiscoveredGIF] = []
    @Published var loading: Bool = false

    private let damus_state: DamusState
    private var searchTask: Task<Void, any Error>?
    private var scourTask: Task<Void, any Error>?
    private var seenIDs = Set<NoteId>()
    private var seenURLs = Set<String>()

    init(damus_state: DamusState) {
        self.damus_state = damus_state
    }

    /// Load GIFs from both kind 1063 metadata events and kind:1 note scouring.
    func load(limit: UInt32 = 200) {
        cancel()
        seenIDs.removeAll()
        seenURLs.removeAll()
        gifs.removeAll()

        searchTask = Task {
            self.loading = true
            await self.queryFileMetadata(limit: limit)
        }

        scourTask = Task {
            await self.scourKind1ForGIFs(limit: limit)
            self.loading = false
        }
    }

    /// Search kind 1063 events by hashtag.
    func search(query: String) {
        guard !query.isEmpty else {
            load()
            return
        }
        cancel()
        seenIDs.removeAll()
        seenURLs.removeAll()
        gifs.removeAll()

        searchTask = Task {
            self.loading = true

            var filter = NostrFilter(kinds: [.file_metadata])
            filter.mime_types = ["image/gif"]
            filter.limit = 100
            filter.until = UInt32(Date.now.timeIntervalSince1970)
            filter.hashtag = [query.lowercased()]

            await self.streamFilter(filter)
            self.loading = false
        }
    }

    func cancel() {
        searchTask?.cancel()
        searchTask = nil
        scourTask?.cancel()
        scourTask = nil
        loading = false
    }

    // MARK: - Kind 1063 query

    private func queryFileMetadata(limit: UInt32) async {
        var filter = NostrFilter(kinds: [.file_metadata])
        filter.mime_types = ["image/gif"]
        filter.limit = limit
        filter.until = UInt32(Date.now.timeIntervalSince1970)

        await streamFilter(filter)
    }

    private func streamFilter(_ filter: NostrFilter) async {
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
                    await self.handleFileMetadataEvent(ev)
                })
            case .eose:
                break
            case .ndbEose:
                break
            case .networkEose:
                break
            }
        }
    }

    @MainActor
    private func handleFileMetadataEvent(_ ev: NostrEvent) {
        guard ev.known_kind == .file_metadata else { return }
        guard !seenIDs.contains(ev.id) else { return }

        // Filter NSFW content when the user preference is set
        if damus_state.settings.hide_nsfw_tagged_content && event_has_content_warning(ev) {
            return
        }

        guard let meta = decode_file_metadata(from: ev), meta.isGIF else {
            return
        }

        let urlKey = meta.url.absoluteString
        guard !seenURLs.contains(urlKey) else { return }

        seenIDs.insert(ev.id)
        seenURLs.insert(urlKey)
        gifs.append(DiscoveredGIF(
            id: ev.id,
            url: meta.url,
            thumbURL: meta.thumbURL ?? meta.imageURL,
            dim: meta.dim,
            alt: meta.alt ?? meta.summary,
            pubkey: ev.pubkey,
            createdAt: ev.created_at
        ))
    }

    // MARK: - Kind:1 GIF URL scour

    private func scourKind1ForGIFs(limit: UInt32) async {
        var filter = NostrFilter(kinds: [.text])
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
                    await self.extractGIFsFromNote(ev)
                })
            case .eose, .ndbEose, .networkEose:
                break
            }
        }
    }

    @MainActor
    private func extractGIFsFromNote(_ ev: NostrEvent) {
        guard ev.known_kind == .text else { return }
        guard !seenIDs.contains(ev.id) else { return }

        guard let blocks = parse_post_blocks(content: ev.content)?.blocks else {
            return
        }

        for block in blocks {
            guard case .url(let url) = block else { continue }
            guard url_is_gif(url) else { continue }

            let urlKey = url.absoluteString
            guard !seenURLs.contains(urlKey) else { continue }

            seenIDs.insert(ev.id)
            seenURLs.insert(urlKey)
            gifs.append(DiscoveredGIF(
                id: ev.id,
                url: url,
                thumbURL: nil,
                dim: nil,
                alt: nil,
                pubkey: ev.pubkey,
                createdAt: ev.created_at
            ))
        }
    }
}

/// Check if a URL points to a GIF by file extension.
func url_is_gif(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    return ext == "gif"
}

/// Check if an event has a content-warning tag (NIP-36) or #nsfw hashtag.
func event_has_content_warning(_ ev: NostrEvent) -> Bool {
    for tag in ev.tags {
        guard tag.count >= 1 else { continue }
        let key = tag[0].string()
        if key == "content-warning" {
            return true
        }
        if key == "t" && tag.count >= 2 && tag[1].string().lowercased() == "nsfw" {
            return true
        }
    }
    return false
}
