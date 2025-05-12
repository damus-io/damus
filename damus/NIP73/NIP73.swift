//
//  NIP73.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-05-09.
//

import Foundation

/// NIP73 structure providing implementations for external content IDs.
struct NIP73 {}

extension NIP73 {
    struct ID: RootableUniqueMultiTagConvertible {        
        var isRootTag: Bool
        var value: Value
        var urlHint: URL?
        
        // MARK: - RootableUniqueMultiTagConvertible protocol implementation
        
        typealias E = TagError
        
        /// Returns the set of tags as defined in NIP-73.
        var tags: [[String]] {
            // Reuse the formatTag method based on whether the tag is a root tag or not.
            return self.formatTag(root: self.isRootTag)
        }
        
        /// Tries to construct an NIP73.ID from an array of TagSequence.
        static func fromTags(tags: TagsSequence, root: Bool) throws(TagError) -> NIP73.ID? {
            let tagStrings = tags.strings()
            return try self.fromTags(tagStrings: tagStrings, root: root)
        }
            
        static func fromTags(tagStrings: [[String]], root: Bool) throws(TagError) -> NIP73.ID? {
            guard let (iRow, kRow) = Self.findRawTagRows(tagStrings: tagStrings, root: root) else { return nil }
            
            guard iRow.count > 1 else { throw .invalidTagFormat("Empty I row") }
            guard kRow.count > 1 else { throw .invalidTagFormat("Empty K row") }
            
            let rawIValue = iRow[1]
            let rawKIdentifier = kRow[1]
            
            guard let knownKind = Value.KnownKind(rawValue: rawKIdentifier) else {
                return NIP73.ID.init(isRootTag: root, value: .unsupported(kind: rawKIdentifier, value: rawIValue))
            }
            
            let value = try Value.from(kind: knownKind, value: rawIValue)
            
            if let urlHintString = iRow[safe: 2] {
                guard let urlHint = URL(string: urlHintString) else {
                    throw .invalidUrlHint
                }
                return NIP73.ID(isRootTag: root, value: value, urlHint: urlHint)
            }
            
            return NIP73.ID(isRootTag: root, value: value, urlHint: nil)
        }
        
        func formatTag(root: Bool) -> [[String]] {
            var urlHintPortion: [String] = []
            if let urlHint { urlHintPortion = [urlHint.absoluteString] }
            return [
                [Self.iTagID(root: root), self.value.value] + urlHintPortion,
                [Self.kTagID(root: root), self.value.kind],
            ]
        }
        
        // MARK: - Helper functions
        
        private static func iTagID(root: Bool) -> String {
            return root ? "I" : "i"
        }
        
        private static func kTagID(root: Bool) -> String {
            return root ? "K" : "k"
        }
        
        private static func findRawTagRows(tagStrings: [[String]], root: Bool) -> (iRow: [String], kRow: [String])? {
            var iRow: [String]?
            var kRow: [String]?
            
            for row in tagStrings {
                guard let first = row.first else { continue }
                if first == Self.iTagID(root: root) {
                    iRow = row
                } else if first == Self.kTagID(root: root) {
                    kRow = row
                }
            }
            
            guard let iRow, let kRow else {
                return nil
            }
            
            return (iRow, kRow)
        }
    }
}


// MARK: - Helper types

extension NIP73.ID {
    enum Value: Hashable {
        case url(url: URL)
        case geo(GeoHash)
        case hashtag(String)
        case unsupported(kind: String, value: String)
        
        var knownKind: KnownKind? {
            switch self {
            case .url(_): return KnownKind.web
            case .geo(_): return KnownKind.geo
            case .hashtag(_): return KnownKind.hashtag
            case .unsupported(_, _): return nil
            }
        }
        
        var kind: String {
            switch self {
            case .url(_): return KnownKind.web.rawValue
            case .geo(_): return KnownKind.geo.rawValue
            case .hashtag(_): return KnownKind.hashtag.rawValue
            case .unsupported(let kind, _): return kind
            }
        }
        
        var value: String {
            switch self {
            case .url(let url): return url.absoluteString
            case .geo(let geohash): return "geo:\(geohash)"
            case .hashtag(let tag): return "#\(tag)"
            case .unsupported(_, let value): return value
            }
        }
        
        var displayName: String {
            switch self {
            case .url(let url): return url.absoluteString
            case .geo(let geohash): return "Somewhere in:\(geohash)"
            case .hashtag(let tag): return "#\(tag)"
            case .unsupported(_, let value): return value
            }
        }
        
        var kindDisplayName: String {
            guard let knownKind else {
                return NSLocalizedString("Unsupported community type", comment: "Label for community type")
            }
            return knownKind.displayName
        }
        
        static func from(kind: KnownKind, value: String) throws(TagError) -> Self {
            switch kind {
            case .web:
                guard let url = URL(string: value) else {
                    throw .invalidTagFormat("Invalid URL in tag: \(value)")
                }
                return .url(url: url)
            case .geo:
                guard let geohash = value.removing(prefix: "geo:") else {
                    throw .invalidTagFormat("Expected `geo:` prefix in tag: '\(value)'")
                }
                return .geo(geohash)
            case .hashtag:
                guard let tagWithoutHash = value.removing(prefix: "#") else {
                    throw .invalidTagFormat("Expected `#` prefix in tag: '\(value)'")
                }
                return .hashtag(tagWithoutHash)
            }
        }
    }
    
    /// An error type for tag conversion failures.
    enum TagError: Error {
        case invalidTagFormat(String)
        case invalidUrlHint
    }
}

fileprivate extension String {
    func removing(prefix: String) -> String? {
        if self.hasPrefix(prefix) {
            return String(self.dropFirst(prefix.count))
        }
        return nil
    }
}

extension NIP73.ID.Value {
    enum KnownKind: String {
        case web = "web"
        case geo = "geo"
        case hashtag = "#"
        
        var displayName: String {
            switch self {
            case .web:
                return NSLocalizedString("Web community", comment: "Label for community type")
            case .geo:
                return NSLocalizedString("Geographical community", comment: "Label for community type")
            case .hashtag:
                return NSLocalizedString("Topic community", comment: "Label for community type")
            }
        }
    }
    
    typealias GeoHash = String
}
