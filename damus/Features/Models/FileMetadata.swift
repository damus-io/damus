//
//  FileMetadata.swift
//  damus
//
//  NIP-94 File Metadata
//  https://github.com/nostr-protocol/nips/blob/master/94.md
//

import Foundation

/// Represents NIP-94 file metadata
struct FileMetadata: Equatable {
    struct RemoteResource: Equatable {
        let url: URL
        let sha256: String?
    }

    let url: URL
    let mimeType: String
    let sha256: String?
    let originalSha256: String?
    let size: Int?
    let dimensions: ImageMetaDim?
    let magnetURI: String?
    let infoHash: String?
    let blurhash: String?
    let thumbnail: RemoteResource?
    let image: RemoteResource?
    let summary: String?
    let alt: String?
    let fallbacks: [URL]
    let service: String?
    let eventId: NoteId?
    let author: Pubkey?
    let relayHints: [RelayURL]
    let publishedAt: UInt32?

    init(
        url: URL,
        mimeType: String = "image/gif",
        sha256: String? = nil,
        originalSha256: String? = nil,
        size: Int? = nil,
        dimensions: ImageMetaDim? = nil,
        magnetURI: String? = nil,
        infoHash: String? = nil,
        blurhash: String? = nil,
        thumbnail: RemoteResource? = nil,
        image: RemoteResource? = nil,
        summary: String? = nil,
        alt: String? = nil,
        fallbacks: [URL] = [],
        service: String? = nil,
        eventId: NoteId? = nil,
        author: Pubkey? = nil,
        relayHints: [RelayURL] = [],
        publishedAt: UInt32? = nil
    ) {
        self.url = url
        self.mimeType = mimeType
        self.sha256 = sha256
        self.originalSha256 = originalSha256
        self.size = size
        self.dimensions = dimensions
        self.magnetURI = magnetURI
        self.infoHash = infoHash
        self.blurhash = blurhash
        self.thumbnail = thumbnail
        self.image = image
        self.summary = summary
        self.alt = alt
        self.fallbacks = fallbacks
        self.service = service
        self.eventId = eventId
        self.author = author
        self.relayHints = relayHints
        self.publishedAt = publishedAt
    }

    func updating(
        eventId: NoteId? = nil,
        author: Pubkey? = nil,
        publishedAt: UInt32? = nil,
        relayHints: [RelayURL]? = nil,
        alt: String? = nil,
        summary: String? = nil
    ) -> FileMetadata {
        FileMetadata(
            url: url,
            mimeType: mimeType,
            sha256: sha256,
            originalSha256: originalSha256,
            size: size,
            dimensions: dimensions,
            magnetURI: magnetURI,
            infoHash: infoHash,
            blurhash: blurhash,
            thumbnail: thumbnail,
            image: image,
            summary: summary ?? self.summary,
            alt: alt ?? self.alt,
            fallbacks: fallbacks,
            service: service,
            eventId: eventId ?? self.eventId,
            author: author ?? self.author,
            relayHints: relayHints ?? self.relayHints,
            publishedAt: publishedAt ?? self.publishedAt
        )
    }

    var previewURL: URL? {
        return thumbnail?.url ?? image?.url ?? url
    }

    /// Convert to ImageMetadata for compatibility with damus's existing media system
    func toImageMetadata() -> ImageMetadata {
        return ImageMetadata(
            url: url,
            blurhash: blurhash,
            dim: dimensions
        )
    }

    func toTags() -> [[String]] {
        var tags: [[String]] = [
            ["url", url.absoluteString],
            ["m", mimeType]
        ]

        if let sha256 {
            tags.append(["x", sha256])
        }
        if let originalSha256 {
            tags.append(["ox", originalSha256])
        }
        if let size {
            tags.append(["size", String(size)])
        }
        if let dimensions {
            tags.append(["dim", dimensions.to_string()])
        }
        if let magnetURI {
            tags.append(["magnet", magnetURI])
        }
        if let infoHash {
            tags.append(["i", infoHash])
        }
        if let blurhash {
            tags.append(["blurhash", blurhash])
        }
        if let summary {
            tags.append(["summary", summary])
        }
        if let alt {
            tags.append(["alt", alt])
        }
        if let service {
            tags.append(["service", service])
        }
        if let thumb = thumbnail {
            var thumbTag = ["thumb", thumb.url.absoluteString]
            if let sha = thumb.sha256 {
                thumbTag.append(sha)
            }
            tags.append(thumbTag)
        }
        if let image = image {
            var imageTag = ["image", image.url.absoluteString]
            if let sha = image.sha256 {
                imageTag.append(sha)
            }
            tags.append(imageTag)
        }
        for fallback in fallbacks {
            tags.append(["fallback", fallback.absoluteString])
        }

        return tags
    }

    func toNostrEvent(
        keypair: FullKeypair,
        content: String = "",
        createdAt: UInt32? = nil
    ) -> NostrEvent? {
        let timestamp = createdAt ?? UInt32(Date().timeIntervalSince1970)
        return NostrEvent(
            content: content,
            keypair: keypair.to_keypair(),
            kind: NostrKind.file_metadata.rawValue,
            tags: toTags(),
            createdAt: timestamp
        )
    }

    static func from(event: NostrEvent, relay: RelayURL? = nil) -> FileMetadata? {
        guard event.known_kind == .file_metadata else {
            return nil
        }
        let tags = event.tags.reduce(into: [[String]]()) { result, tag in
            result.append(tag.strings())
        }

        return FileMetadata.from(
            tags: tags,
            eventId: event.id,
            author: event.pubkey,
            publishedAt: event.created_at,
            relayHints: relay.map { [$0] } ?? []
        )
    }

    static func from(
        tags: [[String]],
        eventId: NoteId? = nil,
        author: Pubkey? = nil,
        publishedAt: UInt32? = nil,
        relayHints: [RelayURL] = []
    ) -> FileMetadata? {
        guard
            let urlString = tags.first(where: { $0.first == "url" })?.dropFirst().first,
            let mimeType = tags.first(where: { $0.first == "m" })?.dropFirst().first,
            let url = URL(string: String(urlString))
        else {
            return nil
        }

        var sha256: String?
        var originalSha256: String?
        var size: Int?
        var dimensions: ImageMetaDim?
        var magnet: String?
        var infoHash: String?
        var blurhash: String?
        var summary: String?
        var alt: String?
        var thumb: RemoteResource?
        var image: RemoteResource?
        var fallbacks: [URL] = []
        var service: String?

        for tag in tags {
            guard let key = tag.first else { continue }
            switch key {
            case "x":
                sha256 = tag[safe: 1]
            case "ox":
                originalSha256 = tag[safe: 1]
            case "size":
                if let raw = tag[safe: 1], let value = Int(raw) {
                    size = value
                }
            case "dim":
                if let raw = tag[safe: 1] {
                    dimensions = ImageMetaDim(from: raw)
                }
            case "magnet":
                magnet = tag[safe: 1]
            case "i":
                infoHash = tag[safe: 1]
            case "blurhash":
                blurhash = tag[safe: 1]
            case "summary":
                summary = tag[safe: 1]
            case "alt":
                alt = tag[safe: 1]
            case "service":
                service = tag[safe: 1]
            case "thumb":
                if let urlString = tag[safe: 1], let thumbURL = URL(string: urlString) {
                    thumb = RemoteResource(url: thumbURL, sha256: tag[safe: 2])
                }
            case "image":
                if let urlString = tag[safe: 1], let imageURL = URL(string: urlString) {
                    image = RemoteResource(url: imageURL, sha256: tag[safe: 2])
                }
            case "fallback":
                if let urlString = tag[safe: 1], let fallbackURL = URL(string: urlString) {
                    fallbacks.append(fallbackURL)
                }
            default:
                continue
            }
        }

        return FileMetadata(
            url: url,
            mimeType: String(mimeType),
            sha256: sha256,
            originalSha256: originalSha256,
            size: size,
            dimensions: dimensions,
            magnetURI: magnet,
            infoHash: infoHash,
            blurhash: blurhash,
            thumbnail: thumb,
            image: image,
            summary: summary,
            alt: alt,
            fallbacks: fallbacks,
            service: service,
            eventId: eventId,
            author: author,
            relayHints: relayHints,
            publishedAt: publishedAt
        )
    }
}

private extension Array where Element == String {
    subscript(safe index: Int) -> String? {
        guard index >= 0 && index < count else {
            return nil
        }
        return self[index]
    }
}
