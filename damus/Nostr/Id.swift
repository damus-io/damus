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

struct QuoteId: IdType, TagKey {
    let id: Data
    
    init(_ data: Data) {
        self.id = data
    }

    var keychar: AsciiCharacter { "q" }
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


struct Hashtag: TagConvertible {
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

struct Signature: Hashable, Equatable {
    let data: Data

    init(_ p: Data) {
        self.data = p
    }
}
