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

    func to_referenced_id() -> ReferencedId {
        ReferencedId(ref_id: id.string(), relay_id: nil, key: key.string)
    }
}

struct References: Sequence, IteratorProtocol {
    let note: NdbNote
    var tags: TagsIterator

    mutating func next() -> Reference? {
        while let tag = tags.next() {
            guard let key = tag[0], key.count == 1,
                  let id = tag[1], id.is_id
            else { continue }

            for c in key {
                guard let a = AsciiCharacter(c) else { break }
                return Reference(key: a, id: id)
            }
        }

        return nil
    }

    init(note: NdbNote) {
        self.note = note
        self.tags = note.tags().makeIterator()
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

