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
    let id: String
    let url: URL
    let thumbURL: URL?
    let dim: ImageMetaDim?
    let alt: String?
    let pubkey: Pubkey?

    init(eventID: NoteId, url: URL, thumbURL: URL? = nil, dim: ImageMetaDim? = nil, alt: String? = nil, pubkey: Pubkey? = nil) {
        self.id = url.absoluteString
        self.url = url
        self.thumbURL = thumbURL
        self.dim = dim
        self.alt = alt
        self.pubkey = pubkey
    }

    init(url: URL) {
        self.id = url.absoluteString
        self.url = url
        self.thumbURL = nil
        self.dim = nil
        self.alt = nil
        self.pubkey = nil
    }
}

/// Queries relays for GIFs via kind 1063 metadata events and kind:1 content scouring.
/// Falls back to a bundled bootstrap catalog when relay results are sparse.
@MainActor
class GIFSearchModel: ObservableObject {
    @Published var gifs: [DiscoveredGIF] = []
    @Published var loading: Bool = false

    private let damus_state: DamusState
    private var loadTask: Task<Void, Never>?
    private var searchTask: Task<Void, any Error>?
    private var seenURLs = Set<String>()

    init(damus_state: DamusState) {
        self.damus_state = damus_state
    }

    /// Load GIFs from both kind 1063 metadata events and kind:1 note scouring.
    /// Immediately shows bootstrap GIFs while relay queries run.
    func load(limit: UInt32 = 200) {
        cancel()
        seenURLs.removeAll()
        gifs.removeAll()

        // Seed with bootstrap catalog immediately
        loadBootstrapGIFs()
        loading = true

        let hideNSFW = damus_state.settings.hide_nsfw_tagged_content
        loadTask = Task {
            async let metadata: Void = self.queryFileMetadata(limit: limit, hideNSFW: hideNSFW)
            async let scour: Void = self.scourKind1ForGIFs(limit: limit, hideNSFW: hideNSFW)
            _ = await (metadata, scour)
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
        seenURLs.removeAll()
        gifs.removeAll()

        let hideNSFW = damus_state.settings.hide_nsfw_tagged_content
        searchTask = Task {
            self.loading = true

            var filter = NostrFilter(kinds: [.file_metadata])
            filter.mime_types = ["image/gif"]
            filter.limit = 100
            filter.until = UInt32(Date.now.timeIntervalSince1970)
            filter.hashtag = [query.lowercased()]

            await self.streamFilter(filter, hideNSFW: hideNSFW)
            self.loading = false
        }
    }

    func cancel() {
        loadTask?.cancel()
        loadTask = nil
        searchTask?.cancel()
        searchTask = nil
        loading = false
    }

    // MARK: - Bootstrap catalog

    @MainActor
    private func loadBootstrapGIFs() {
        guard let urls = load_bootstrap_gif_urls() else { return }

        for url in urls.shuffled() {
            let urlKey = url.absoluteString
            guard !seenURLs.contains(urlKey) else { continue }
            seenURLs.insert(urlKey)
            gifs.append(DiscoveredGIF(url: url))
        }
    }

    // MARK: - Kind 1063 query

    private func queryFileMetadata(limit: UInt32, hideNSFW: Bool) async {
        var filter = NostrFilter(kinds: [.file_metadata])
        filter.mime_types = ["image/gif"]
        filter.limit = limit
        filter.until = UInt32(Date.now.timeIntervalSince1970)

        await streamFilter(filter, hideNSFW: hideNSFW)
    }

    private func streamFilter(_ filter: NostrFilter, hideNSFW: Bool) async {
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
                    await self.processFileMetadataEvent(ev, hideNSFW: hideNSFW)
                })
            case .eose, .ndbEose, .networkEose:
                break
            }
        }
    }

    // MARK: - Kind:1 GIF URL scour

    private func scourKind1ForGIFs(limit: UInt32, hideNSFW: Bool) async {
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
                    await self.processKind1Event(ev, hideNSFW: hideNSFW)
                })
            case .eose, .ndbEose, .networkEose:
                break
            }
        }
    }

    // MARK: - Nonisolated event parsing (off MainActor)

    /// Parse kind 1063 file metadata off the main thread, then commit result on MainActor.
    nonisolated private func processFileMetadataEvent(_ ev: NostrEvent, hideNSFW: Bool) async {
        guard ev.known_kind == .file_metadata else { return }
        if hideNSFW && event_has_content_warning(ev) { return }
        guard let meta = decode_file_metadata(from: ev), meta.isGIF else { return }

        let gif = DiscoveredGIF(
            eventID: ev.id,
            url: meta.url,
            thumbURL: meta.thumbURL ?? meta.imageURL,
            dim: meta.dim,
            alt: meta.alt ?? meta.summary,
            pubkey: ev.pubkey
        )
        await self.commitGIF(gif)
    }

    /// Parse kind:1 note content for GIF URLs off the main thread, then commit on MainActor.
    nonisolated private func processKind1Event(_ ev: NostrEvent, hideNSFW: Bool) async {
        guard ev.known_kind == .text else { return }
        if hideNSFW && event_has_content_warning(ev) { return }
        guard let blocks = parse_post_blocks(content: ev.content)?.blocks else { return }

        let pubkey = ev.pubkey
        let eventID = ev.id
        var parsed: [DiscoveredGIF] = []
        for block in blocks {
            guard case .url(let url) = block else { continue }
            guard url_is_gif(url) else { continue }
            parsed.append(DiscoveredGIF(eventID: eventID, url: url, pubkey: pubkey))
        }

        if !parsed.isEmpty {
            await self.commitGIFs(parsed)
        }
    }

    // MARK: - State mutations (MainActor)

    private func commitGIF(_ gif: DiscoveredGIF) {
        let urlKey = gif.url.absoluteString
        guard !seenURLs.contains(urlKey) else { return }
        seenURLs.insert(urlKey)
        gifs.append(gif)
    }

    private func commitGIFs(_ newGIFs: [DiscoveredGIF]) {
        for gif in newGIFs {
            commitGIF(gif)
        }
    }
}

// MARK: - Helpers

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

/// Load the bundled bootstrap GIF URL catalog.
func load_bootstrap_gif_urls() -> [URL]? {
    guard let path = Bundle.main.path(forResource: "bootstrap_gifs", ofType: "json"),
          let data = FileManager.default.contents(atPath: path),
          let strings = try? JSONDecoder().decode([String].self, from: data)
    else {
        return nil
    }
    return strings.compactMap { URL(string: $0) }
}
