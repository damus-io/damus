//
//  Id.swift
//  damus
//
//  Created by William Casarin on 2023-07-26.
//

import Foundation

struct TagRef<T>: Hashable, Equatable, Encodable {
    let elem: TagElem

    init(_ elem: TagElem) {
        self.elem = elem
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(elem.string())
    }
}

protocol TagKey {
    var keychar: AsciiCharacter { get }
}

protocol TagKeys {
    associatedtype TagKeys: TagKey
    var key: TagKeys { get }
}

protocol TagConvertible {
    var tag: [String] { get }
    static func from_tag(tag: TagSequence) -> Self?
}

/// Protocol for types that can be converted from/to a tag sequence with the possibilty of an error
protocol ThrowingTagConvertible {
    associatedtype E: Error
    var tag: [String] { get }
    static func fromTag(tag: TagSequence) throws(E) -> Self?
}

/// Protocol for types that can be converted from/to a tag item
protocol TagItemConvertible {
    var tagItem: String? { get }
    static func fromTagItem(_ item: String?) -> Self?
}

struct QuoteId: IdType, TagKey, TagConvertible {
    let id: Data

    init(_ data: Data) {
        self.id = data
    }

    /// The note id being quoted
    var note_id: NoteId {
        NoteId(self.id)
    }

    var keychar: AsciiCharacter { "q" }

    var tag: [String] {
        ["q", self.hex()]
    }

    static func from_tag(tag: TagSequence) -> QuoteId? {
        var i = tag.makeIterator()

        guard tag.count >= 2,
              let t0 = i.next(),
              let key = t0.single_char,
              key == "q",
              let t1 = i.next(),
              let quote_id = t1.id().map(QuoteId.init)
        else { return nil }

        return quote_id
    }
}

/// A quote reference with optional relay hints for fetching.
///
/// Per NIP-10/NIP-18, `q` tags include a relay URL at position 2 where the quoted
/// event can be found.
///
/// Note: The NIPs allow `q` tags to contain either event IDs (hex) or event addresses
/// (`<kind>:<pubkey>:<d>` for replaceable events). This implementation currently only
/// supports hex event IDs; quotes of addressable events are not yet handled.
struct QuoteRef: TagConvertible {
    let quote_id: QuoteId
    let relayHints: [RelayURL]

    /// The note ID being quoted
    var note_id: NoteId {
        quote_id.note_id
    }

    var tag: [String] {
        var tagBuilder = ["q", quote_id.hex()]
        if let relay = relayHints.first {
            tagBuilder.append(relay.absoluteString)
        }
        return tagBuilder
    }

    /// Parses a `q` tag into a QuoteRef, preserving relay hints from position 2.
    ///
    /// Only parses `q` tags containing hex event IDs. Tags with event addresses
    /// (`<kind>:<pubkey>:<d>`) are not currently supported and will return nil.
    static func from_tag(tag: TagSequence) -> QuoteRef? {
        var i = tag.makeIterator()

        guard tag.count >= 2,
              let t0 = i.next(),
              let key = t0.single_char,
              key == "q",
              let t1 = i.next(),
              let data = t1.id()
        else { return nil }

        let quoteId = QuoteId(data)
        let relayHints = tag.relayHints
        return QuoteRef(quote_id: quoteId, relayHints: relayHints)
    }
}


struct Privkey: IdType {
    let id: Data

    var nsec: String {
        bech32_privkey(self)
    }

    init?(hex: String) {
        guard let id = hex_decode_id(hex) else {
            return nil
        }
        self.init(id)
    }

    init(_ data: Data) {
        self.id = data
    }
}


struct Hashtag: TagConvertible, Hashable {
    let hashtag: String

    static func from_tag(tag: TagSequence) -> Hashtag? {
        var i = tag.makeIterator()

        guard tag.count >= 2,
              let t0 = i.next(),
              let chr = t0.single_char,
              chr == "t",
              let t1 = i.next() else {
            return nil
        }

        return Hashtag(hashtag: t1.string())
    }

    var tag: [String] { ["t", self.hashtag] }
    var keychar: AsciiCharacter { "t" }
}

struct ReplaceableParam: TagConvertible {
    let param: TagElem

    static func from_tag(tag: TagSequence) -> ReplaceableParam? {
        var i = tag.makeIterator()

        guard tag.count >= 2,
              let t0 = i.next(),
              let chr = t0.single_char,
              chr == "d",
              let t1 = i.next() else {
            return nil
        }

        return ReplaceableParam(param: t1)
    }

    var tag: [String] { [self.keychar.description, self.param.string()] }
    var keychar: AsciiCharacter { "d" }
}

struct Signature: Codable, Hashable, Equatable {
    let data: Data
    
    init(from decoder: Decoder) throws {
        self.init(try hex_decoder(decoder, expected_len: 64))
    }

    func encode(to encoder: Encoder) throws {
        try hex_encoder(to: encoder, data: self.data)
    }

    init(_ p: Data) {
        self.data = p
    }
}
