import Foundation

/// The single primary recording described by a signed NIP-808 event.
/// This validates references only. Downloaded bytes still require hash/container verification.
struct VoiceMediaReference: Codable, Equatable, Sendable {
    /// Preserve the exact server-returned spelling, including opaque paths and queries.
    let url: String
    let sha256: String
    let mimeType: String
    /// Advisory only; the verified media's measured duration controls playback.
    let statedDuration: TimeInterval?

    private enum CodingKeys: String, CodingKey { case url, sha256, mimeType, statedDuration }

    /// A saved receipt must pass the same validation as wire metadata.
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        var tags = [
            ["url", try values.decode(String.self, forKey: .url)],
            ["blossom", try values.decode(String.self, forKey: .sha256), try values.decode(String.self, forKey: .mimeType)]
        ]
        if let duration = try values.decodeIfPresent(TimeInterval.self, forKey: .statedDuration), duration.isFinite, duration >= 0 {
            tags.append(["duration", String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), duration)])
        }
        try self.init(tags: tags)
    }

    /// Parse the authoritative tags, checking all repetitions instead of choosing the first.
    init(tags: [[String]]) throws {
        let urls = tags.filter { $0.first == "url" }
        let blossoms = tags.filter { $0.first == "blossom" }
        guard let primaryURL = urls.first, primaryURL.count >= 2,
              Self.isHTTPSURL(primaryURL[1]),
              urls.allSatisfy({ $0.count >= 2 && $0[1] == primaryURL[1] }) else {
            throw ReferenceError.invalidURL
        }
        guard let primaryBlob = blossoms.first, primaryBlob.count >= 3,
              Self.isSHA256(primaryBlob[1]),
              Self.isAudioMIME(primaryBlob[2]),
              blossoms.allSatisfy({
                  $0.count >= 3 && $0[1] == primaryBlob[1] &&
                  Self.normalizedMIME($0[2]) == Self.normalizedMIME(primaryBlob[2])
              }) else {
            throw ReferenceError.invalidBlob
        }

        let expectedURL = primaryURL[1]
        let expectedHash = primaryBlob[1]
        let expectedMIME = Self.normalizedMIME(primaryBlob[2])
        for tag in tags {
            switch tag.first {
            case "x":
                guard tag.count >= 2, tag[1] == expectedHash else {
                    throw ReferenceError.conflictingMetadata
                }
            case "m":
                guard tag.count >= 2, Self.normalizedMIME(tag[1]) == expectedMIME else {
                    throw ReferenceError.conflictingMetadata
                }
            case "imeta":
                try Self.checkAttachment(tag, url: expectedURL, hash: expectedHash, mime: expectedMIME)
            default:
                break
            }
        }

        self.url = expectedURL
        self.sha256 = expectedHash
        self.mimeType = expectedMIME
        let durations = tags.filter { $0.first == "duration" }
        let parsed = durations.map { $0.count >= 2 ? Self.parseDuration($0[1]) : nil }
        if let first = parsed.first ?? nil, parsed.allSatisfy({ $0 == first }) {
            self.statedDuration = first
        } else {
            self.statedDuration = nil
        }
    }

    /// Receipts may omit duration; outgoing events add the measured recording duration.
    init(url: String, sha256: String, mimeType: String, duration: TimeInterval? = nil) throws {
        var tags = [["url", url], ["blossom", sha256, mimeType]]
        if let duration {
            guard duration.isFinite, duration >= 0 else { throw ReferenceError.invalidDuration }
            tags.append(["duration", String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), duration)])
        }
        try self.init(tags: tags)
    }

    /// Outgoing recordings have measured duration; incoming absent duration stays absent.
    var tags: [[String]] {
        var tags = [["url", url], ["blossom", sha256, mimeType]]
        if let statedDuration {
            tags.append(["duration", String(format: "%.3f", locale: Locale(identifier: "en_US_POSIX"), statedDuration)])
        }
        return tags
    }

    /// Validate the direct HTTPS reference without reconstructing it from the hash.
    static func isHTTPSURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil,
              components.fragment == nil, components.url != nil else { return false }
        if let port = components.port, !(1...65535).contains(port) { return false }
        return !value.contains(where: { $0.isWhitespace || $0.isNewline })
    }

    /// NIP-808 uses exactly 32 bytes represented by lowercase hexadecimal.
    static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    /// MIME tokens are case insensitive; parameters remain part of the declaration.
    static func normalizedMIME(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Unknown audio encodings remain readable as transcripts even if playback lacks a decoder.
    private static func isAudioMIME(_ value: String) -> Bool {
        guard !value.contains(where: { $0.isNewline }) else { return false }
        let normalized = normalizedMIME(value)
        guard normalized.hasPrefix("audio/") else { return false }
        let subtype = normalized.dropFirst("audio/".count)
        let punctuation = Set("!#$%&'*+-.^_`|~".utf8)
        return !subtype.isEmpty && subtype.utf8.allSatisfy {
            (97...122).contains($0) || (48...57).contains($0) || punctuation.contains($0)
        }
    }

    /// Treat invalid or conflicting stated durations as absent, never as a playback failure.
    private static func parseDuration(_ value: String) -> TimeInterval? {
        guard value.range(of: "^[0-9]+(?:\\.[0-9]+)?$", options: .regularExpression) != nil,
              let duration = Double(value), duration.isFinite, duration >= 0 else { return nil }
        return duration
    }

    /// Supplementary metadata for this recording must agree; unrelated covers stay separate.
    private static func checkAttachment(_ tag: [String], url: String, hash: String, mime: String) throws {
        let fields = tag.dropFirst().map { $0.split(separator: " ", maxSplits: 1).map(String.init) }
        let urls = fields.filter { $0.first == "url" }.map { $0.count == 2 ? $0[1] : "" }
        let hashes = fields.filter { $0.first == "x" }.map { $0.count == 2 ? $0[1] : "" }
        let types = fields.filter { $0.first == "m" }.map { $0.count == 2 ? normalizedMIME($0[1]) : "" }
        let declaresAudio = types.contains { $0.hasPrefix("audio/") }
        guard declaresAudio || urls.contains(url) || hashes.contains(hash) else { return }
        guard urls.allSatisfy({ $0 == url }), hashes.allSatisfy({ $0 == hash }),
              types.allSatisfy({ $0 == mime }) else { throw ReferenceError.conflictingMetadata }
    }

    /// Stable validation failures that preserve the signed transcript in the UI.
    enum ReferenceError: LocalizedError, Equatable {
        case invalidURL, invalidBlob, conflictingMetadata, invalidDuration

        var errorDescription: String? {
            switch self {
            case .invalidURL: return "This voice post has no valid recording URL."
            case .invalidBlob: return "This voice post has no valid recording hash and audio type."
            case .conflictingMetadata: return "The recording references disagree. Audio cannot be verified."
            case .invalidDuration: return "The recording duration could not be measured."
            }
        }
    }
}
