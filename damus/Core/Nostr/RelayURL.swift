//
//  RelayURL.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-09-29.
//

import Foundation

public struct RelayURL: Hashable, Equatable, Codable, CodingKeyRepresentable, Identifiable, Comparable, CustomStringConvertible, Sendable {
    private(set) var url: URL

    public var id: URL {
        return url
    }

    public var description: String {
        return self.absoluteString
    }

    public var absoluteString: String {
        return url.absoluteString
    }

    init?(_ str: String) {
        var trimmed_url_str = str
        while trimmed_url_str.hasSuffix("/") {
            trimmed_url_str.removeLast()
        }

        guard let url = URL(string: trimmed_url_str) else {
            return nil
        }

        guard let scheme = url.scheme else {
            return nil
        }
        
        guard scheme == "ws" || scheme == "wss" else {
            return nil
        }
        
        self.url = url
    }
    
    // MARK: - Codable
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let urlString = try container.decode(String.self)
        guard let instance = RelayURL(urlString) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid URL string.")
        }
        self = instance
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(url.absoluteString)
    }
    
    // MARK: - CodingKeyRepresentable
    // CodingKeyRepresentable conformance is necessary to ensure that
    // a dictionary with type "[RelayURL: T] where T: Codable" can be encoded into a keyed container
    // e.g. `{<URL>: <VALUE>, <URL>: <VALUE>}` instead of `[<URL>, <VALUE>, <URL>, <VALUE>]`, which is Swift's default for non-string-keyed dictionaries
    
    public var codingKey: CodingKey {
        return StringKey(stringValue: self.url.absoluteString)
    }
    
    public init?<T>(codingKey: T) where T : CodingKey {
        self.init(codingKey.stringValue)
    }
    
    // MARK: - Equatable
    public static func == (lhs: RelayURL, rhs: RelayURL) -> Bool {
        return lhs.url == rhs.url
    }
    
    // MARK: - Hashable
    public func hash(into hasher: inout Hasher) {
        hasher.combine(self.url)
    }

    // MARK: - Comparable
    public static func < (lhs: RelayURL, rhs: RelayURL) -> Bool {
        return lhs.url.absoluteString < rhs.url.absoluteString
    }

}

extension RelayURL {
    /// Shared relay used by the Vine short-video feed.
    static let vineRelay = RelayURL("wss://relay.divine.video")!
}

private struct StringKey: CodingKey {
    var stringValue: String
    init(stringValue: String) {
        self.stringValue = stringValue
    }
    var intValue: Int? { return nil }
    init?(intValue: Int) { return nil }
}
