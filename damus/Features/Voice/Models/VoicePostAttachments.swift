import Foundation

/// A photo owned by the current audio composition. Only the uploaded URL enters its event.
struct VoicePhotoAttachment: Codable, Equatable, Sendable, Identifiable {
    let id: UUID
    var url: String?
    let dim: String
    var blurhash: String?

    /// Each photo has its own metadata; these fields never describe the primary audio.
    func tag() throws -> [String] {
        guard let url, VoiceMediaReference.isHTTPSURL(url) else {
            throw VoiceFailure("A photo has not finished uploading.")
        }
        var tag = ["imeta", "url " + url, "m image/jpeg", "dim " + dim]
        if let blurhash { tag.append("blurhash " + blurhash) }
        return tag
    }
}

/// Structured attachments keep references separate from the device-generated transcript.
struct VoicePostAttachments: Codable, Equatable, Sendable {
    var mentions: [String] = []
    var links: [String] = []
    var photos: [VoicePhotoAttachment] = []
    var isEmpty: Bool { mentions.isEmpty && links.isEmpty && photos.isEmpty }

    /// Accept web URLs, never local file paths or executable/custom URL schemes.
    static func webURL(_ input: String) throws -> String {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.utf8.count <= 2048,
              let parts = URLComponents(string: value),
              ["http", "https"].contains(parts.scheme?.lowercased() ?? ""),
              parts.host?.isEmpty == false, parts.user == nil, parts.password == nil,
              let url = parts.url else { throw VoiceFailure("Enter a complete http:// or https:// web link.") }
        return url.absoluteString
    }

    /// NIP-808 uses NIP-27 mentions, ordinary content links, and one imeta tag per image.
    func payload() throws -> (content: [String], tags: [[String]]) {
        guard mentions.count <= 100, links.count <= 20, photos.count <= 8 else {
            throw VoiceFailure("This post has too many attachments.")
        }
        var content: [String] = []
        var tags: [[String]] = []
        for hex in mentions {
            guard let pubkey = Pubkey(hex: hex) else { throw VoiceFailure("A mentioned profile is invalid.") }
            content.append("nostr:" + pubkey.npub)
            tags.append(["p", pubkey.hex()])
        }
        for link in links {
            let url = try Self.webURL(link)
            content.append(url)
            tags.append(["r", url])
        }
        for photo in photos {
            let tag = try photo.tag()
            content.append(String(tag[1].dropFirst(4)))
            tags.append(tag)
        }
        return (content, tags)
    }
}
