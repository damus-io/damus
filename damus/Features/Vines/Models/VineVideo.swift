//
//  VineVideo.swift
//  damus
//
//  Extracted from PostingTimelineView.swift on 2026-02-10.
//

import Foundation

/// A parsed representation of a Vine short-video Nostr event (kind 34236).
///
/// Parses `imeta` tags per NIP-71 / NIP-92: each `imeta` tag is a separate
/// media variant (e.g. 1080p mp4 vs 720p HLS). The best variant is selected
/// by mime-type priority (mp4 > HLS > other). Within a variant, `url` and
/// `fallback` URLs are weighted equally per spec.
///
/// - Note: `@unchecked Sendable` because the sole reference-type field (`event:
///   NostrEvent`) is an `NdbNote` whose mutable properties (`decrypted_content`,
///   `owned`) are never written by `VineVideo`.
public struct VineVideo: Identifiable, Equatable, @unchecked Sendable {

    // MARK: - NIP-71 Types

    /// A single `imeta` tag parsed into its constituent key-value properties.
    /// Each imeta tag represents one media variant (resolution / format).
    private struct IMetaVariant {
        var url: URL?
        var mimeType: String?
        var dim: String?
        var duration: String?
        var bitrate: String?
        var images: [URL] = []
        var fallbacks: [URL] = []
        var blurhash: String?
        var service: String?
        var hash: String?
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

    /// A chapter marker within a video (NIP-71 `segment` tag).
    struct VideoSegment: Equatable {
        let start: String
        let end: String
        let title: String?
        let thumbnailURL: URL?
    }

    /// A WebVTT text track reference (NIP-71 `text-track` tag).
    struct TextTrack: Equatable {
        let content: String
        let relayURLs: String?
    }

    // MARK: - Properties

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
    let bitrate: String?
    let origin: VineOrigin?
    let proofTags: [VineProof]
    let segments: [VideoSegment]
    let textTracks: [TextTrack]
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

    // MARK: - Init

    init?(event: NostrEvent, repostSource: NostrEvent? = nil) {
        guard event.known_kind == .vine_short else { return nil }
        self.event = event

        let content = event.content.trimmingCharacters(in: .whitespacesAndNewlines)
        self.summary = content.isEmpty ? nil : content
        self.hashtags = event.referenced_hashtags.map(\.hashtag)

        // Parse each imeta tag as a separate media variant (NIP-71)
        let variants = VineVideo.parseIMetaVariants(from: event)

        self.title = VineVideo.tagValue("title", in: event) ?? summary ?? NSLocalizedString("Untitled Vine", comment: "Fallback title when a Vine video is missing metadata.")
        self.contentWarning = VineVideo.tagValue("content-warning", in: event) ?? VineVideo.tagValue("cw", in: event)
        self.altText = VineVideo.tagValue("alt", in: event)
        self.durationDescription = VineVideo.tagValue("duration", in: event) ?? variants.compactMap(\.duration).first
        self.dimensionDescription = VineVideo.tagValue("dim", in: event) ?? variants.compactMap(\.dim).first
        self.bitrate = variants.compactMap(\.bitrate).first
        self.origin = VineVideo.origin(from: event)
        self.proofTags = VineVideo.proofTags(from: event)
        self.segments = VineVideo.segments(from: event)
        self.textTracks = VineVideo.textTracks(from: event)
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

        // Select best playback URL from imeta variants
        let selection = VineVideo.selectPlayback(from: variants)

        if let primary = selection.primary {
            self.playbackURL = primary
        } else if let contentURL = VineVideo.firstVideoURL(in: content) {
            // Last resort: extract URL from content text for malformed events
            self.playbackURL = contentURL
        } else {
            Log.debug("VineVideo missing playable URL for event %s", for: .timeline, event.id.hex())
            return nil
        }

        self.fallbackURL = selection.fallback
        self.thumbnailURL = selection.thumbnail ?? VineVideo.thumbnailFromStandaloneTags(in: event)
        self.blurhash = selection.blurhash ?? VineVideo.tagValue("blurhash", in: event)
    }

    var requiresBlur: Bool {
        contentWarning != nil
    }

    // MARK: - imeta Variant Parsing (NIP-71 / NIP-92)

    /// Parses each `imeta` tag into a separate `IMetaVariant`.
    /// Handles both NIP-92 inline format (`"key value"`) and paired format (`key`, `value`).
    private static func parseIMetaVariants(from event: NostrEvent) -> [IMetaVariant] {
        var variants: [IMetaVariant] = []
        for tag in event.tags {
            let values = tag.strings()
            guard values.first == "imeta" else { continue }
            let payload = Array(values.dropFirst())

            var entries: [(String, String)] = []
            let usesInlineFormat = payload.contains(where: { $0.contains(" ") })
            if usesInlineFormat {
                for element in payload {
                    let parts = element.split(separator: " ", maxSplits: 1)
                    guard parts.count == 2 else { continue }
                    entries.append((String(parts[0]), String(parts[1])))
                }
            } else {
                var iterator = payload.makeIterator()
                while let key = iterator.next(), let value = iterator.next() {
                    entries.append((key, value))
                }
            }

            var variant = IMetaVariant()
            for (key, value) in entries {
                switch key {
                case "url":
                    if let url = normalizedURL(value) { variant.url = url }
                case "m":
                    variant.mimeType = value
                case "dim":
                    variant.dim = value
                case "duration":
                    variant.duration = value
                case "bitrate":
                    variant.bitrate = value
                case "image":
                    if let url = normalizedURL(value) { variant.images.append(url) }
                case "fallback":
                    if let url = normalizedURL(value) { variant.fallbacks.append(url) }
                case "blurhash":
                    variant.blurhash = value
                case "service":
                    variant.service = value
                case "x":
                    variant.hash = value
                default:
                    break
                }
            }
            variants.append(variant)
        }
        return variants
    }

    // MARK: - Playback URL Selection

    /// Selects the best playback URL from parsed imeta variants.
    /// Prefers mp4 > other video > HLS/DASH. Within a variant, `url` and `fallback`
    /// are weighted equally per NIP-71.
    private static func selectPlayback(from variants: [IMetaVariant]) -> (primary: URL?, fallback: URL?, thumbnail: URL?, blurhash: String?) {
        let sorted = variants.sorted { lhs, rhs in
            mimeTypePriority(lhs.mimeType) < mimeTypePriority(rhs.mimeType)
        }

        // Primary: best variant's url (or first fallback if url is nil)
        guard let best = sorted.first else {
            return (nil, nil, nil, nil)
        }
        let primary = best.url ?? best.fallbacks.first

        // Fallback: a streaming variant if available (different from primary variant)
        let streamingURL: URL? = sorted.dropFirst().first(where: {
            $0.mimeType == "application/x-mpegURL" || $0.mimeType == "application/dash+xml"
        })?.url

        // If the primary is already HLS, use a non-HLS variant as fallback instead
        let fallback: URL?
        if best.mimeType == "application/x-mpegURL" || best.mimeType == "application/dash+xml" {
            fallback = sorted.dropFirst().compactMap(\.url).first
        } else {
            fallback = streamingURL
        }

        // Thumbnail: from best variant, then fall through other variants
        let thumbnail = best.images.first ?? sorted.compactMap(\.images.first).first
        let blurhash = best.blurhash ?? sorted.compactMap(\.blurhash).first

        return (primary, fallback, thumbnail, blurhash)
    }

    private static func mimeTypePriority(_ mimeType: String?) -> Int {
        switch mimeType {
        case "video/mp4", "video/quicktime": return 0
        case "video/webm": return 1
        case "application/x-mpegURL": return 2
        case "application/dash+xml": return 3
        default: return 4
        }
    }

    // MARK: - Thumbnail from Standalone Tags

    private static func thumbnailFromStandaloneTags(in event: NostrEvent) -> URL? {
        if let direct = tagValue("thumb", in: event), let url = normalizedURL(direct) {
            return url
        }
        if let image = tagValue("image", in: event), let url = normalizedURL(image) {
            return url
        }
        return nil
    }

    // MARK: - Content URL Fallback

    /// Last-resort extraction of a video URL from the event content text.
    /// Used only when no imeta tags provide a playback URL.
    private static func firstVideoURL(in content: String?) -> URL? {
        guard let content, !content.isEmpty else { return nil }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        let range = NSRange(content.startIndex..<content.endIndex, in: content)
        let matches = detector.matches(in: content, options: [], range: range)
        for match in matches {
            guard let matchRange = Range(match.range, in: content) else { continue }
            let urlString = String(content[matchRange])
            guard let url = normalizedURL(urlString) else { continue }
            let ext = url.pathExtension.lowercased()
            if ["mp4", "mov", "m3u8", "mpd", "webm"].contains(ext) {
                return url
            }
        }
        return nil
    }

    // MARK: - URL Normalization

    /// Normalises a raw URL string.
    /// Workaround: rewrites the known typo domain "apt.openvine.co" -> "api.openvine.co"
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

    // MARK: - NIP-71 Tag Parsers

    private static func segments(from event: NostrEvent) -> [VideoSegment] {
        var result: [VideoSegment] = []
        for tag in event.tags {
            let values = tag.strings()
            guard values.first == "segment", values.count >= 3 else { continue }
            let start = values[1]
            let end = values[2]
            let title = values.count > 3 ? values[3] : nil
            let thumbURL = values.count > 4 ? normalizedURL(values[4]) : nil
            result.append(VideoSegment(start: start, end: end, title: title, thumbnailURL: thumbURL))
        }
        return result
    }

    private static func textTracks(from event: NostrEvent) -> [TextTrack] {
        var result: [TextTrack] = []
        for tag in event.tags {
            let values = tag.strings()
            guard values.first == "text-track", values.count >= 2 else { continue }
            let content = values[1]
            let relayURLs = values.count > 2 ? values[2] : nil
            result.append(TextTrack(content: content, relayURLs: relayURLs))
        }
        return result
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

    // MARK: - Helpers

    /// Returns a shortened npub like `npub1abc...wxyz` for display.
    private static func truncatedNpub(_ npub: String) -> String {
        guard npub.count > 12 else { return npub }
        return "\(npub.prefix(8))…\(npub.suffix(4))"
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
}
