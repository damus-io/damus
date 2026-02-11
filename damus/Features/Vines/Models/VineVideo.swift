//
//  VineVideo.swift
//  damus
//
//  Extracted from PostingTimelineView.swift on 2026-02-10.
//

import Foundation

/// A parsed representation of a Vine short-video Nostr event (kind 34236).
///
/// Extracts playback URLs, thumbnails, engagement stats, and metadata from the
/// event's tag set. Immutable after construction — the contained `NostrEvent` is
/// only read, never mutated.
///
/// - Note: `@unchecked Sendable` because the sole reference-type field (`event:
///   NostrEvent`) is an `NdbNote` whose mutable properties (`decrypted_content`,
///   `owned`) are never written by `VineVideo`.
public struct VineVideo: Identifiable, Equatable, @unchecked Sendable {
    struct MediaCandidate: Hashable {
        enum Kind: Hashable {
            case mp4
            case mov
            case hls
            case dash
            case fallback
            case unknown

            var priority: Int {
                switch self {
                case .mp4, .mov:
                    return 0
                case .hls:
                    return 1
                case .dash, .fallback:
                    return 2
                case .unknown:
                    return 3
                }
            }
        }

        enum Source: Hashable {
            case direct
            case imeta(String)
            case streaming(String?)
            case reference(String?)
            case content
            case fallback

            var priority: Int {
                switch self {
                case .direct, .imeta:
                    return 0
                case .reference:
                    return 1
                case .streaming:
                    return 2
                case .content:
                    return 3
                case .fallback:
                    return 4
                }
            }
        }

        let url: URL
        let kind: Kind
        let source: Source

        var priority: Int {
            (source.priority * 10) + kind.priority
        }
    }

    struct VineOrigin: Equatable {
        let source: String
        let identifier: String?
        let detail: String?

        var displayText: String {
            if let identifier, let detail {
                return "\(source) • \(identifier) – \(detail)"
            } else if let identifier {
                return "\(source) • \(identifier)"
            } else if let detail {
                return "\(source) – \(detail)"
            } else {
                return source
            }
        }
    }

    struct VineProof: Equatable {
        let key: String
        let values: [String]
    }

    private struct IMetaEntry {
        let key: String
        let value: String
    }

    let event: NostrEvent
    let dedupeKey: String
    let title: String
    let summary: String?
    let authorDisplay: String
    let createdAt: UInt32
    let hashtags: [String]
    let playbackURL: URL?
    let fallbackURL: URL?
    let thumbnailURL: URL?
    let blurhash: String?
    let contentWarning: String?
    let altText: String?
    let durationDescription: String?
    let dimensionDescription: String?
    let origin: VineOrigin?
    let proofTags: [VineProof]
    let expirationTimestamp: UInt32?
    let loopCount: Int?
    let likeCount: Int?
    let commentCount: Int?
    let repostCount: Int?
    let publishedAt: String?
    let repostedBy: String?
    let repostedAt: UInt32?

    public var id: String { event.id.hex() }
    var originDescription: String? { origin?.displayText }

    init?(event: NostrEvent, repostSource: NostrEvent? = nil) {
        guard event.known_kind == .vine_short else { return nil }
        self.event = event

        let content = event.content.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = content.isEmpty ? nil : content
        self.hashtags = event.referenced_hashtags.map(\.hashtag)
        let imetaEntries = VineVideo.imetaEntries(in: event)
        self.title = VineVideo.tagValue("title", in: event) ?? summary ?? NSLocalizedString("Untitled Vine", comment: "Fallback title when a Vine video is missing metadata.")
        self.contentWarning = VineVideo.contentWarning(from: event, imetaEntries: imetaEntries)
        self.altText = VineVideo.altText(from: event, imetaEntries: imetaEntries)
        self.durationDescription = VineVideo.duration(from: event, imetaEntries: imetaEntries)
        self.dimensionDescription = VineVideo.dimension(from: event, imetaEntries: imetaEntries)
        self.origin = VineVideo.origin(from: event)
        self.proofTags = VineVideo.proofTags(from: event)
        self.expirationTimestamp = VineVideo.expirationTimestamp(from: event)
        self.loopCount = VineVideo.intTagValue("loops", in: event)
        self.likeCount = VineVideo.intTagValue("likes", in: event)
        self.commentCount = VineVideo.intTagValue("comments", in: event)
        self.repostCount = VineVideo.intTagValue("reposts", in: event)
        self.publishedAt = VineVideo.tagValue("published_at", in: event)
        if let repost = repostSource {
            self.repostedBy = VineVideo.truncatedNpub(repost.pubkey.npub)
            self.repostedAt = repost.created_at
        } else {
            self.repostedBy = nil
            self.repostedAt = nil
        }

        self.dedupeKey = VineVideo.tagValue("d", in: event) ?? event.id.hex()
        self.createdAt = event.created_at
        self.authorDisplay = VineVideo.truncatedNpub(event.pubkey.npub)

        var candidateMap: [URL: MediaCandidate] = [:]
        VineVideo.collectDirectURLs(from: event, into: &candidateMap)
        VineVideo.collectIMetaURLs(from: imetaEntries, into: &candidateMap)
        VineVideo.collectStreamingURLs(from: event, into: &candidateMap)
        VineVideo.collectReferenceURLs(from: event, into: &candidateMap)
        VineVideo.collectContentURLs(from: content, into: &candidateMap)
        if candidateMap.isEmpty {
            VineVideo.collectFallbackURLs(from: event, into: &candidateMap)
        }

        let sorted = candidateMap.values.sorted { lhs, rhs in
            if lhs.priority == rhs.priority {
                return lhs.url.absoluteString < rhs.url.absoluteString
            }
            return lhs.priority < rhs.priority
        }
        guard let primaryURL = sorted.first?.url else {
            Log.debug("VineVideo missing playable URL for event %s", for: .timeline, event.id.hex())
            return nil
        }

        self.playbackURL = primaryURL
        self.fallbackURL = sorted.dropFirst().first(where: { $0.kind == .hls || $0.kind == .dash })?.url
        self.thumbnailURL = VineVideo.thumbnailURL(from: event, imetaEntries: imetaEntries)
        self.blurhash = VineVideo.blurhash(from: event, imetaEntries: imetaEntries)
    }

    var requiresBlur: Bool {
        contentWarning != nil
    }

    /// Returns a shortened npub like `npub1abc…wxyz` for display.
    private static func truncatedNpub(_ npub: String) -> String {
        guard npub.count > 12 else { return npub }
        return "\(npub.prefix(8))…\(npub.suffix(4))"
    }

    private static func collectDirectURLs(from event: NostrEvent, into candidates: inout [URL: MediaCandidate]) {
        for tag in event.tags {
            let values = tag.strings()
            guard values.first == "url", values.count > 1,
                  let url = normalizedURL(values[1]) else { continue }
            addCandidate(url, kind: mediaKind(for: url), source: .direct, into: &candidates)
        }
    }

    private static func collectIMetaURLs(from entries: [IMetaEntry], into candidates: inout [URL: MediaCandidate]) {
        for entry in entries {
            switch entry.key {
            case "url", "video", "mp4":
                guard let url = normalizedURL(entry.value) else { continue }
                addCandidate(url, kind: mediaKind(forMetaKey: entry.key, url: url), source: .imeta(entry.key), into: &candidates)
            case "fallback":
                guard let url = normalizedURL(entry.value) else { continue }
                addCandidate(url, kind: .fallback, source: .imeta(entry.key), into: &candidates)
            case "hls", "stream", "streaming":
                guard let url = normalizedURL(entry.value) else { continue }
                addCandidate(url, kind: .hls, source: .imeta(entry.key), into: &candidates)
            case "dash":
                guard let url = normalizedURL(entry.value) else { continue }
                addCandidate(url, kind: .dash, source: .imeta(entry.key), into: &candidates)
            default:
                continue
            }
        }
    }

    private static func collectStreamingURLs(from event: NostrEvent, into candidates: inout [URL: MediaCandidate]) {
        for tag in event.tags {
            let values = tag.strings()
            guard values.first == "streaming", values.count >= 2,
                  let url = normalizedURL(values[1]) else { continue }
            let format = values.count >= 3 ? values[2] : nil
            let kind: MediaCandidate.Kind = mediaKind(for: url)
            addCandidate(url, kind: kind, source: .streaming(format), into: &candidates)
        }
    }

    private static func collectReferenceURLs(from event: NostrEvent, into candidates: inout [URL: MediaCandidate]) {
        for tag in event.tags {
            let values = tag.strings()
            guard let first = values.first else { continue }
            switch first {
            case "r":
                guard values.count > 1,
                      let url = normalizedURL(values[1]) else { continue }
                let type = values.count > 2 ? values[2] : nil
                if let type, type == "thumbnail" {
                    continue
                }
                addCandidate(url, kind: mediaKind(for: url), source: .reference(type), into: &candidates)
            case "e", "i":
                guard values.count > 1,
                      let url = normalizedURL(values[1]) else { continue }
                addCandidate(url, kind: mediaKind(for: url), source: .reference(first), into: &candidates)
            default:
                continue
            }
        }
    }

    private static func collectContentURLs(from content: String?, into candidates: inout [URL: MediaCandidate]) {
        guard let content, !content.isEmpty else { return }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = detector.matches(in: content, options: [], range: range)
        for match in matches {
            guard let matchRange = Range(match.range, in: content) else { continue }
            let urlString = String(content[matchRange])
            guard let url = normalizedURL(urlString) else { continue }
            addCandidate(url, kind: mediaKind(for: url), source: .content, into: &candidates)
        }
    }

    private static func collectFallbackURLs(from event: NostrEvent, into candidates: inout [URL: MediaCandidate]) {
        for tag in event.tags {
            let values = tag.strings().dropFirst()
            for value in values {
                guard let url = normalizedURL(value) else { continue }
                addCandidate(url, kind: mediaKind(for: url), source: .fallback, into: &candidates)
            }
        }
    }

    private static func addCandidate(_ url: URL, kind: MediaCandidate.Kind, source: MediaCandidate.Source, into candidates: inout [URL: MediaCandidate]) {
        let candidate = MediaCandidate(url: url, kind: kind, source: source)
        if let existing = candidates[url], existing.priority <= candidate.priority {
            return
        }
        candidates[url] = candidate
    }

    private static func mediaKind(for url: URL) -> MediaCandidate.Kind {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mp4":
            return .mp4
        case "mov":
            return .mov
        case "m3u8":
            return .hls
        case "mpd":
            return .dash
        default:
            return .unknown
        }
    }

    private static func mediaKind(forMetaKey key: String, url: URL) -> MediaCandidate.Kind {
        switch key {
        case "url", "mp4", "video":
            return mediaKind(for: url)
        case "hls", "stream":
            return .hls
        case "dash":
            return .dash
        case "fallback":
            return .fallback
        default:
            return mediaKind(for: url)
        }
    }

    /// Normalises a raw URL string for use in media candidates.
    /// Workaround: rewrites the known typo domain "apt.openvine.co" → "api.openvine.co"
    /// that appears in some early Vine events. Remove once upstream data is corrected.
    private static func normalizedURL(_ raw: String) -> URL? {
        var cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        cleaned = cleaned.replacingOccurrences(of: "apt.openvine.co", with: "api.openvine.co")
        guard let url = URL(string: cleaned),
              let scheme = url.scheme,
              scheme == "https" || scheme == "http" else {
            return nil
        }
        return url
    }

    private static func thumbnailURL(from event: NostrEvent, imetaEntries: [IMetaEntry]) -> URL? {
        if let direct = tagValue("thumb", in: event), let url = normalizedURL(direct) {
            return url
        }
        if let image = tagValue("image", in: event), let url = normalizedURL(image) {
            return url
        }
        if let imetaImage = imetaEntries.first(where: { $0.key == "image" || $0.key == "thumb" }), let url = normalizedURL(imetaImage.value) {
            return url
        }
        for tag in event.tags {
            let values = tag.strings()
            guard values.first == "r", values.count > 2 else { continue }
            guard values[2] == "thumbnail", let url = normalizedURL(values[1]) else { continue }
            return url
        }
        return nil
    }

    private static func blurhash(from event: NostrEvent, imetaEntries: [IMetaEntry]) -> String? {
        if let tagValue = tagValue("blurhash", in: event) {
            return tagValue
        }
        return imetaEntries.first(where: { $0.key == "blurhash" })?.value
    }

    private static func contentWarning(from event: NostrEvent, imetaEntries: [IMetaEntry]) -> String? {
        if let tagValue = tagValue("content-warning", in: event) ?? tagValue("cw", in: event) {
            return tagValue
        }
        return imetaEntries.first(where: { $0.key == "content-warning" || $0.key == "cw" })?.value
    }

    private static func altText(from event: NostrEvent, imetaEntries: [IMetaEntry]) -> String? {
        if let tagValue = tagValue("alt", in: event) {
            return tagValue
        }
        return imetaEntries.first(where: { $0.key == "alt" })?.value
    }

    private static func duration(from event: NostrEvent, imetaEntries: [IMetaEntry]) -> String? {
        if let tagValue = tagValue("duration", in: event) {
            return tagValue
        }
        return imetaEntries.first(where: { $0.key == "duration" })?.value
    }

    private static func dimension(from event: NostrEvent, imetaEntries: [IMetaEntry]) -> String? {
        if let tagValue = tagValue("dim", in: event) {
            return tagValue
        }
        return imetaEntries.first(where: { $0.key == "dim" })?.value
    }

    private static func origin(from event: NostrEvent) -> VineOrigin? {
        for tag in event.tags {
            let values = tag.strings()
            guard values.first == "origin" else { continue }
            let source = values.indices.contains(1) ? values[1] : "origin"
            let identifier = values.indices.contains(2) ? values[2] : nil
            let detail = values.indices.contains(3) ? values[3] : nil
            return VineOrigin(source: source, identifier: identifier, detail: detail)
        }
        return nil
    }

    private static func proofTags(from event: NostrEvent) -> [VineProof] {
        event.tags.strings().compactMap { tag in
            guard let key = tag.first else { return nil }
            if key == "proof" || key.hasPrefix("pm-") || key == "pm-report" {
                return VineProof(key: key, values: Array(tag.dropFirst()))
            }
            return nil
        }
    }

    private static func expirationTimestamp(from event: NostrEvent) -> UInt32? {
        guard let value = tagValue("expiration", in: event) ?? tagValue("expires_at", in: event),
              let intVal = UInt32(value) else { return nil }
        return intVal
    }

    private static func intTagValue(_ key: String, in event: NostrEvent) -> Int? {
        guard let value = tagValue(key, in: event) else { return nil }
        return Int(value)
    }

    private static func tagValue(_ key: String, in event: NostrEvent) -> String? {
        for tag in event.tags {
            let values = tag.strings()
            guard values.first == key else { continue }
            return values.count > 1 ? values[1] : nil
        }
        return nil
    }

    private static func imetaEntries(in event: NostrEvent) -> [IMetaEntry] {
        var entries: [IMetaEntry] = []
        for tag in event.tags {
            let values = tag.strings()
            guard values.first == "imeta" else { continue }
            let payload = Array(values.dropFirst())
            let usesInlineFormat = payload.contains(where: { $0.contains(" ") })
            if usesInlineFormat {
                for element in payload {
                    let parts = element.split(separator: " ", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    entries.append(IMetaEntry(key: String(parts[0]), value: String(parts[1])))
                }
            } else {
                var iterator = payload.makeIterator()
                while let key = iterator.next(), let value = iterator.next() {
                    entries.append(IMetaEntry(key: key, value: value))
                }
            }
        }
        return entries
    }
}
