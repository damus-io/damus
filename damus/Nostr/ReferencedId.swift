//
//  ReferencedId.swift
//  damus
//
//  Created by William Casarin on 2023-07-22.
//

import Foundation

struct Reference {
    let key: AsciiCharacter
    let id: NdbTagElem
    var ref_id: NdbTagElem {
        id
    }

    func to_referenced_id() -> ReferencedId {
        ReferencedId(ref_id: id.string(), relay_id: nil, key: key.string)
    }
}

func tagref_should_be_id(_ tag: NdbTagElem) -> Bool {
    return !tag.matches_char("t")
}

struct References: Sequence, IteratorProtocol {
    let tags: TagsSequence
    var tags_iter: TagsIterator

    mutating func next() -> Reference? {
        while let tag = tags_iter.next() {
            guard tag.count >= 2 else { continue }
            let key = tag[0]
            let id  = tag[1]

            guard key.count == 1, tagref_should_be_id(id) else { continue }

            for c in key {
                guard let a = AsciiCharacter(c) else { break }
                return Reference(key: a, id: id)
            }
        }

        return nil
    }


    static func ids(tags: TagsSequence) -> LazyFilterSequence<References> {
        References(tags: tags).lazy
            .filter() { ref in ref.key == "e" }
    }

    static func pubkeys(tags: TagsSequence) -> LazyFilterSequence<References> {
        References(tags: tags).lazy
            .filter() { ref in ref.key == "p" }
    }

    static func hashtags(tags: TagsSequence) -> LazyFilterSequence<References> {
        References(tags: tags).lazy
            .filter() { ref in ref.key == "t" }
    }

    init(tags: TagsSequence) {
        self.tags = tags
        self.tags_iter = tags.makeIterator()
    }
}

// TagsSequence transition helpers
extension [[String]] {
    func strings() -> [[String]] {
        return self
    }
}

// TagsSequence transition helpers
extension [String] {
    func strings() -> [String] {
        return self
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

struct ReferencedId: Identifiable, Hashable, Equatable {
    let ref_id: String
    let relay_id: String?
    let key: String

    var id: String {
        return ref_id
    }
    
    static func q(_ id: String, relay_id: String? = nil) -> ReferencedId {
        return ReferencedId(ref_id: id, relay_id: relay_id, key: "q")
    }
    
    static func e(_ id: String, relay_id: String? = nil) -> ReferencedId {
        return ReferencedId(ref_id: id, relay_id: relay_id, key: "e")
    }

    static func p(_ pk: String, relay_id: String? = nil) -> ReferencedId {
        return ReferencedId(ref_id: pk, relay_id: relay_id, key: "p")
    }

    static func t(_ hashtag: String, relay_id: String? = nil) -> ReferencedId {
        return ReferencedId(ref_id: hashtag, relay_id: relay_id, key: "t")
    }
}

