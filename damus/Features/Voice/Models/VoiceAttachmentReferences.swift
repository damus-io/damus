import Foundation

/// Read-side attachments are independent of the primary, verified voice recording.
/// Classifying these references performs no network or database work.
struct VoiceAttachmentReferences {
    enum Kind { case image, video, link }

    struct Attachment: Equatable {
        let url: URL
        let kind: Kind
        let title: String?
    }

    let attachments: [Attachment]

    /// Merge content URLs, NIP-808 imeta/r tags, then any remaining cached URLs.
    /// This order repairs old partial caches without rearranging attachment tags.
    /// Every declared primary URL is excluded even when its recording tags are invalid.
    init(tags: [[String]], contentURLs: [URL] = [], cachedURLs: [URL] = []) {
        let primary = Set(tags.filter { $0.first == "url" && $0.count > 1 }
            .compactMap { URL(string: $0[1]) }.map(Self.identity))
        var taggedURLs: [URL] = []
        var mediaTypes: [String: Set<String>] = [:]
        var titles: [String: String] = [:]

        for tag in tags {
            if tag.first == "imeta" {
                let fields = tag.dropFirst().compactMap { field -> (String, String)? in
                    let parts = field.split(separator: " ", maxSplits: 1)
                    guard parts.count == 2 else { return nil }
                    return (String(parts[0]), String(parts[1]))
                }
                let urlFields = fields.filter { $0.0 == "url" }
                let urls = urlFields.compactMap { Self.remoteURL($0.1) }
                guard let url = urls.first, urls.count == urlFields.count,
                      Set(urls).count == 1 else { continue }
                let key = Self.identity(url)
                let types = fields.filter { $0.0 == "m" }
                    .map { VoiceMediaReference.normalizedMIME($0.1) }.filter { !$0.isEmpty }
                mediaTypes[key, default: []].formUnion(types)
                taggedURLs.append(url)
            } else if tag.first == "r", tag.count > 1, let url = Self.remoteURL(tag[1]) {
                taggedURLs.append(url)
                if tag.count > 2, !tag[2].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    titles[Self.identity(url)] = tag[2]
                }
            }
        }

        var seen = Set<String>()
        attachments = (contentURLs + taggedURLs + cachedURLs).compactMap { url in
            guard Self.remoteURL(url.absoluteString) != nil else { return nil }
            let key = Self.identity(url)
            guard !primary.contains(key), seen.insert(key).inserted else { return nil }
            let kind = Self.kind(url: url, mediaTypes: mediaTypes[key])
            return Attachment(url: url, kind: kind, title: titles[key])
        }
    }

    /// Comparison only: fragments and default ports do not identify different downloaded bytes.
    /// Never use this normalized identity as the URL sent to a media server.
    static func identity(_ url: URL) -> String {
        guard var parts = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return url.absoluteString }
        parts.fragment = nil
        parts.scheme = parts.scheme?.lowercased()
        parts.host = parts.host?.lowercased()
        if (parts.scheme == "https" && parts.port == 443) || (parts.scheme == "http" && parts.port == 80) {
            parts.port = nil
        }
        if parts.percentEncodedPath.isEmpty { parts.percentEncodedPath = "/" }
        return parts.string ?? url.absoluteString
    }

    /// Hide raw image URLs represented by attachments, retaining other links and their attributes.
    /// Remove an image-only line with its separator so it does not leave an empty paragraph.
    static func hidingImageURLs(in content: AttributedString, imageURLs: [URL]) -> AttributedString {
        let images = Set(imageURLs.map(identity))
        let ranges = content.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard let url = run.link, images.contains(identity(url)),
                  String(content[run.range].characters) == url.absoluteString else { return nil }
            return run.range
        }
        guard !ranges.isEmpty else { return content }

        var result = content
        for range in ranges.reversed() {
            let characters = result.characters
            var start = range.lowerBound
            var end = range.upperBound
            while start > characters.startIndex {
                let previous = characters.index(before: start)
                guard characters[previous].isWhitespace, !characters[previous].isNewline else { break }
                start = previous
            }
            while end < characters.endIndex, characters[end].isWhitespace, !characters[end].isNewline {
                end = characters.index(after: end)
            }
            let startsLine = start == characters.startIndex || characters[characters.index(before: start)].isNewline
            let endsLine = end == characters.endIndex || characters[end].isNewline
            guard startsLine && endsLine else {
                result.removeSubrange(range)
                continue
            }
            if end < characters.endIndex {
                end = characters.index(after: end)
            } else if start > characters.startIndex {
                start = characters.index(before: start)
            }
            result.removeSubrange(start..<end)
        }
        while let last = result.characters.last, last.isWhitespace {
            result.removeSubrange(result.characters.index(before: result.endIndex)..<result.endIndex)
        }
        return result
    }

    /// Attachments follow ordinary web media rules; local files and other schemes cannot embed.
    private static func remoteURL(_ value: String) -> URL? {
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              let parts = URLComponents(string: value),
              let scheme = parts.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return nil }
        return parts.url
    }

    /// Declared MIME wins over suffixes, including opaque URLs and audio in MP4 containers.
    /// Conflicting or unsupported declarations remain links instead of guessing a media type.
    private static func kind(url: URL, mediaTypes: Set<String>?) -> Kind {
        if let mediaTypes, !mediaTypes.isEmpty {
            guard mediaTypes.count == 1, let mime = mediaTypes.first else { return .link }
            if mime.hasPrefix("image/") { return .image }
            if mime.hasPrefix("video/") { return .video }
            return .link
        }
        switch url.pathExtension.lowercased() {
        case "png", "jpg", "jpeg", "gif", "webp": return .image
        case "mp4", "mov", "m3u8", "m4v", "webm": return .video
        case "m4a", "mp3", "aac", "wav", "flac", "aiff", "ogg", "opus": return .link
        default:
            // NIP-808 image imeta fields are optional; an opaque image URL needs no suffix.
            return mediaTypes == nil ? .link : .image
        }
    }
}
