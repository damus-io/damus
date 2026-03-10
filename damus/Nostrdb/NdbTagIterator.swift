//
//  NdbTagIterators.swift
//  damus
//
//  Created by William Casarin on 2023-07-21.
//

import Foundation


/// The sequence of strings in a single nostr event tag
///
/// Example 1:
/// ```json
///   ["r", "wss://nostr-relay.example.com", "read"]
/// ```
///
/// Example 2:
/// ```json
///   ["p", "8b2be0a0ad34805d76679272c28a77dbede9adcbfdca48c681ec8b624a1208a6"]
/// ```
struct TagSequence: Sequence {
    let note: NdbNote
    let tag: ndb_tag_ptr

    var count: UInt16 {
        ndb_tag_count(tag.ptr)
    }

    func strings() -> [String] {
        return self.map { $0.string() }
    }

    subscript(index: Int) -> NdbTagElem {
        precondition(index < count, "Index out of bounds")

        return NdbTagElem(note: note, tag: tag, index: Int32(index))
    }

    func makeIterator() -> TagIterator {
        return TagIterator(note: note, tag: tag)
    }
}

// MARK: - Relay Hint Extraction

extension TagSequence {
    /// Extracts a relay URL hint from position 2 of the tag, if present and valid.
    ///
    /// Per NIP-01 and NIP-10, position 2 in `e`, `p`, `a`, and `q` tags contains an optional
    /// relay URL where the referenced entity may be found.
    ///
    /// Example tag: `["e", "<event-id>", "wss://relay.example.com"]`
    ///
    /// - Returns: A valid `RelayURL` if position 2 contains a non-empty, valid relay URL; `nil` otherwise.
    var relayHint: RelayURL? {
        guard count >= 3 else { return nil }
        let urlString = self[2].string()
        guard !urlString.isEmpty else { return nil }
        return RelayURL(urlString)
    }

    /// Extracts relay hints from the tag as an array.
    ///
    /// Currently tags only support a single relay hint at position 2, but this method
    /// returns an array for consistency with `NEvent.relays` and future extensibility.
    ///
    /// - Returns: An array containing the relay hint if present, or an empty array.
    var relayHints: [RelayURL] {
        guard let hint = relayHint else { return [] }
        return [hint]
    }
}

struct TagIterator: IteratorProtocol {
    typealias Element = NdbTagElem

    mutating func next() -> NdbTagElem? {
        guard index < ndb_tag_count(tag.ptr) else { return nil }
        let el = NdbTagElem(note: note, tag: tag, index: index)

        index += 1

        return el
    }

    var index: Int32
    let note: NdbNote
    var tag: ndb_tag_ptr

    var count: UInt16 {
        ndb_tag_count(tag.ptr)
    }

    init(note: NdbNote, tag: ndb_tag_ptr) {
        self.note = note
        self.tag = tag
        self.index = 0
    }
}
