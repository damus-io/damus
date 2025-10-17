//
//  GIFCatalogBootstrap.swift
//  damus
//
//  Helper utilities for publishing curated GIF metadata events (NIP-94).
//

import Foundation

enum GIFCatalogBootstrapError: Error, LocalizedError {
    case signingFailed

    var errorDescription: String? {
        switch self {
        case .signingFailed:
            return NSLocalizedString("Unable to sign metadata event.", comment: "Publishing error")
        }
    }
}

struct GIFCatalogEntry: Codable, Hashable {
    let url: URL
    let title: String
    let description: String
    let tags: [String]
    let mimeType: String
    let width: Int?
    let height: Int?
    let sizeInBytes: Int?
    let thumbnailURL: URL?

    init(
        url: URL,
        title: String,
        description: String,
        tags: [String],
        mimeType: String = "image/gif",
        width: Int? = nil,
        height: Int? = nil,
        sizeInBytes: Int? = nil,
        thumbnailURL: URL? = nil
    ) {
        self.url = url
        self.title = title
        self.description = description
        self.tags = tags
        self.mimeType = mimeType
        self.width = width
        self.height = height
        self.sizeInBytes = sizeInBytes
        self.thumbnailURL = thumbnailURL
    }

    func toMetadata(relayHints: [RelayURL] = []) -> FileMetadata {
        let dimensions: ImageMetaDim?
        if let width, let height {
            dimensions = ImageMetaDim(width: width, height: height)
        } else {
            dimensions = nil
        }

        let previewResource = thumbnailURL.map { FileMetadata.RemoteResource(url: $0, sha256: nil) }

        return FileMetadata(
            url: url,
            mimeType: mimeType,
            size: sizeInBytes,
            dimensions: dimensions,
            thumbnail: previewResource,
            summary: title,
            alt: description,
            fallbacks: [],
            service: "nostr",
            relayHints: relayHints
        )
    }
}

enum GIFCatalogBootstrap {
    static func getStarterCatalog() -> [GIFCatalogEntry] {
        return [
            GIFCatalogEntry(
                url: URL(string: "https://media.giphy.com/media/OkJat1YNdoD3W/giphy.gif")!,
                title: "Thumbs up",
                description: "Thumbs up approval",
                tags: ["thumbsup", "approve", "yes"]
            ),
            GIFCatalogEntry(
                url: URL(string: "https://media.giphy.com/media/l3q2K5jinAlChoCLS/giphy.gif")!,
                title: "Clapping",
                description: "Applause and clapping",
                tags: ["clap", "cheer", "applause"]
            ),
            GIFCatalogEntry(
                url: URL(string: "https://media.giphy.com/media/3o6ZtaO9BZHcOjmErm/giphy.gif")!,
                title: "Nod of agreement",
                description: "Confident nod",
                tags: ["nod", "agree", "yes"]
            ),
            GIFCatalogEntry(
                url: URL(string: "https://media.giphy.com/media/5GoVLqeAOo6PK/giphy.gif")!,
                title: "Laughing hard",
                description: "Laugh out loud",
                tags: ["laugh", "lol", "funny"]
            ),
            GIFCatalogEntry(
                url: URL(string: "https://media.giphy.com/media/ROF8OQvDmxytW/giphy.gif")!,
                title: "Crying",
                description: "Tears flowing",
                tags: ["cry", "sad", "emotion"]
            ),
            GIFCatalogEntry(
                url: URL(string: "https://media.giphy.com/media/l0HUpt2s9Pclgt9Vm/giphy.gif")!,
                title: "Shocked",
                description: "Shocked reaction",
                tags: ["shocked", "surprised", "wow"]
            ),
            GIFCatalogEntry(
                url: URL(string: "https://media.giphy.com/media/3oEjI6SIIHBdRxXI40/giphy.gif")!,
                title: "Thinking",
                description: "Thinking face",
                tags: ["think", "ponder", "hmm"]
            ),
            GIFCatalogEntry(
                url: URL(string: "https://media.giphy.com/media/13d2jHlSlxklVe/giphy.gif")!,
                title: "Confused",
                description: "Confused shrug",
                tags: ["confused", "shrug", "idk"]
            ),
            GIFCatalogEntry(
                url: URL(string: "https://media.giphy.com/media/l46Cy1rHbQ92uuLXa/giphy.gif")!,
                title: "Mind blown",
                description: "Mind blown reaction",
                tags: ["mindblown", "wow", "surprised"]
            ),
            GIFCatalogEntry(
                url: URL(string: "https://media.giphy.com/media/3o6wrvdHFbwBrUFenu/giphy.gif")!,
                title: "Facepalm",
                description: "Disappointed facepalm",
                tags: ["facepalm", "no", "disapprove"]
            ),
            GIFCatalogEntry(
                url: URL(string: "https://media.giphy.com/media/26ufdipQqU2lhNA4g/giphy.gif")!,
                title: "Shaking head",
                description: "Shaking head disapproval",
                tags: ["no", "disagree", "disapprove"]
            ),
            GIFCatalogEntry(
                url: URL(string: "https://media.giphy.com/media/3oriO7A7bt1wsEP4cw/giphy.gif")!,
                title: "Dancing",
                description: "Happy dancing",
                tags: ["dance", "party", "excited"]
            ),
            GIFCatalogEntry(
                url: URL(string: "https://media.giphy.com/media/3o85xIO33l7RlmLR4I/giphy.gif")!,
                title: "High five",
                description: "Successful high five",
                tags: ["highfive", "celebrate", "team"]
            ),
            GIFCatalogEntry(
                url: URL(string: "https://media.giphy.com/media/ctZDVdAXESeqY/giphy.gif")!,
                title: "Popcorn",
                description: "Watching with popcorn",
                tags: ["popcorn", "watching", "drama"]
            ),
            GIFCatalogEntry(
                url: URL(string: "https://media.giphy.com/media/3oz8xAFtqoOUUrsh7W/giphy.gif")!,
                title: "Applause",
                description: "Standing applause",
                tags: ["applause", "bravo", "clap"]
            )
        ]
    }

    static func publishGIF(
        _ entry: GIFCatalogEntry,
        keypair: FullKeypair,
        relayHints: [RelayURL] = []
    ) throws -> (event: NostrEvent, metadata: FileMetadata) {
        let metadata = entry.toMetadata(relayHints: relayHints)
        let baseTags = metadata.toTags() + entry.tags.map { ["t", $0.lowercased()] }

        guard let event = NostrEvent(
            content: entry.description,
            keypair: keypair.to_keypair(),
            kind: NostrKind.file_metadata.rawValue,
            tags: baseTags
        ) else {
            throw GIFCatalogBootstrapError.signingFailed
        }

        let enrichedMetadata = metadata.updating(
            eventId: event.id,
            author: event.pubkey,
            publishedAt: event.created_at,
            relayHints: relayHints
        )

        return (event, enrichedMetadata)
    }

    static func batchPublishGIFs(
        _ entries: [GIFCatalogEntry],
        keypair: FullKeypair,
        postbox: PostBox? = nil,
        relayHints: [RelayURL] = [],
        progress: ((Int, Int) -> Void)? = nil
    ) async throws -> [NostrEvent] {
        var events: [NostrEvent] = []
        for (index, entry) in entries.enumerated() {
            try Task.checkCancellation()
            let (event, _) = try publishGIF(entry, keypair: keypair, relayHints: relayHints)
            events.append(event)
            postbox?.send(event)
            progress?(index + 1, entries.count)
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        return events
    }
}
