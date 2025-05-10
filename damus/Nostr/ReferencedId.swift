//
//  ReferencedId.swift
//  damus
//
//  Created by William Casarin on 2023-07-22.
//

import Foundation

func tagref_should_be_id(_ tag: NdbTagElem) -> Bool {
    return !(tag.matches_char("t") || tag.matches_char("d"))
}


struct References<T: TagConvertible>: Sequence, IteratorProtocol {
    let tags: TagsSequence
    var tags_iter: TagsIterator

    init(tags: TagsSequence) {
        self.tags = tags
        self.tags_iter = tags.makeIterator()
    }

    mutating func next() -> T? {
        while let tag = tags_iter.next() {
            guard let evref = T.from_tag(tag: tag) else { continue }
            return evref
        }
        return nil
    }
}

extension References {
    var first: T? {
        self.first(where: { _ in true })
    }

    var last: T? {
        var last: T? = nil
        for t in self {
            last = t
        }
        return last
    }
}


// NdbTagElem transition helpers
extension String {
    func string() -> String {
        return self
    }

    func first_char() -> AsciiCharacter? {
        self.first.flatMap { chr in AsciiCharacter(chr) }
    }

    func matches_char(_ c: AsciiCharacter) -> Bool {
        return self.first == c.character
    }
    
    func matches_str(_ str: String) -> Bool {
        return self == str
    }
}

enum FollowRef: TagKeys, Hashable, TagConvertible, Equatable {

    // NOTE: When adding cases make sure to update key and from_tag
    case pubkey(Pubkey)
    case hashtag(String)

    var key: FollowKeys {
        switch self {
        case .hashtag: return .t
        case .pubkey:  return .p
        }
    }

    enum FollowKeys: AsciiCharacter, TagKey, CustomStringConvertible {
        case p, t

        var keychar: AsciiCharacter { self.rawValue }
        var description: String { self.rawValue.description }
    }

    static func from_tag(tag: TagSequence) -> FollowRef? {
        guard tag.count >= 2 else { return nil }

        var i = tag.makeIterator()

        guard let t0   = i.next(),
              let c    = t0.single_char,
              let fkey = FollowKeys(rawValue: c),
              let t1   = i.next()
        else {
            return nil
        }

        switch fkey {
        case .p: return t1.id().map({ .pubkey(Pubkey($0)) })
        case .t: return .hashtag(t1.string())
        }
    }

    var tag: [String] {
        [key.description, self.description]
    }

    var description: String {
        switch self {
        case .pubkey(let pubkey): return pubkey.description
        case .hashtag(let string): return string
        }
    }
}

/// Models common tag references defined by the Nostr protocol, and their associated values.
///
/// For example, this raw JSON tag sequence:
/// ```json
///   ["p", "8b2be0a0ad34805d76679272c28a77dbede9adcbfdca48c681ec8b624a1208a6"]
/// ```
///
/// would be parsed into something equivalent to `.pubkey(Pubkey(hex: "8b2be0a0ad34805d76679272c28a77dbede9adcbfdca48c681ec8b624a1208a6"))`
///
/// ## Notes
///
/// - Not all tag information from all NIPs can be modelled using this alone, as some NIPs may define extra associated values for specific event types. You may need to use a specialized type for some event kinds
///
enum RefId: TagConvertible, TagKeys, Equatable, Hashable {
    case event(NoteId)
    case pubkey(Pubkey)
    case quote(QuoteId)
    case hashtag(Hashtag)
    case param(TagElem)
    case naddr(NAddr)
    case community(NIP73.ID.Value)
    case reference(String)
    
    /// The key that defines the type of reference being made
    var key: RefKey {
        switch self {
        case .event:        return .e
        case .pubkey:       return .p
        case .quote:        return .q
        case .hashtag:      return .t
        case .param:        return .d
        case .naddr:        return .a
        case .reference:    return .r
        case .community:    return .I
        }
    }

    /// Defines the type of reference being made on a Nostr event tag
    ///
    /// Example:
    /// ```json
    ///   ["p", "8b2be0a0ad34805d76679272c28a77dbede9adcbfdca48c681ec8b624a1208a6"]
    /// ```
    ///
    /// The `RefKey` is "p"
    enum RefKey: AsciiCharacter, TagKey, CustomStringConvertible {
        case e, p, t, d, q, a, r, I

        var keychar: AsciiCharacter {
            self.rawValue
        }

        var description: String {
            self.keychar.description
        }
    }

    /// A raw nostr-style tag sequence representation of this object
    var tag: [String] {
        [self.key.description, self.description]
    }
    
    /// Describes what is being referenced, as a `String`
    var description: String {
        switch self {
        case .event(let noteId): return noteId.hex()
        case .pubkey(let pubkey): return pubkey.hex()
        case .quote(let quote): return quote.hex()
        case .hashtag(let string): return string.hashtag
        case .param(let string): return string.string()
        case .naddr(let naddr):
            return naddr.kind.description + ":" + naddr.author.hex() + ":" + naddr.identifier
        case .reference(let string):
            return string
        case .community(let value):
            return value.value
        }
    }

    /// Parses a raw tag sequence
    static func from_tag(tag: TagSequence) -> RefId? {
        var i = tag.makeIterator()

        guard tag.count >= 2,
              let t0 = i.next(),
              let key = t0.single_char,
              let rkey = RefKey(rawValue: key),
              let t1 = i.next()
        else { return nil }

        switch rkey {
        case .e: return t1.id().map({ .event(NoteId($0)) })
        case .p: return t1.id().map({ .pubkey(Pubkey($0)) })
        case .q: return t1.id().map({ .quote(QuoteId($0)) })
        case .t: return .hashtag(Hashtag(hashtag: t1.string()))
        case .d: return .param(t1)
        case .a: return .naddr(NAddr(identifier: "", author: Pubkey(Data()), relays: [], kind: 0))
        case .r: return .reference(t1.string())
        case .I:
            guard let value = try? NIP73.ID.Value.from(kind: .hashtag, value: t1.string()) else { return nil }  // TODO: Remove hardcoded stuff
            return .community(value)
        }
    }
}

