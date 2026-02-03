//
//  Referenced.swift
//  damus
//
//  Created by William Casarin on 2023-07-28.
//

import Foundation

enum Marker: String {
    case root
    case reply
    case mention

    init?(_ tag: TagElem) {
        let len = tag.count

        if len == 4, tag.matches_str("root", tag_len: len) {
            self = .root
        } else if len == 5, tag.matches_str("reply", tag_len: len) {
            self = .reply
        } else if len == 7, tag.matches_str("mention", tag_len: len) {
            self = .mention
        } else {
            return nil
        }
    }
}

/// A reference to a note event, with optional relay hint, marker, and author pubkey.
/// Per NIP-10: `["e", <event-id>, <relay-url>, <marker>, <pubkey>]`
struct NoteRef: IdType, TagConvertible, Equatable {
    let note_id: NoteId
    let relay: String?
    let marker: Marker?
    let pubkey: Pubkey?

    var id: Data {
        self.note_id.id
    }

    init(note_id: NoteId, relay: String? = nil, marker: Marker? = nil, pubkey: Pubkey? = nil) {
        self.note_id = note_id
        self.relay = relay
        self.marker = marker
        self.pubkey = pubkey
    }

    static func note_id(_ note_id: NoteId) -> NoteRef {
        return NoteRef(note_id: note_id)
    }

    init(_ data: Data) {
        self.note_id = NoteId(data)
        self.relay = nil
        self.marker = nil
        self.pubkey = nil
    }

    /// Generates a tag array per NIP-10: `["e", <event-id>, <relay-url>, <marker>, <pubkey>]`
    var tag: [String] {
        var t = ["e", self.hex()]
        if let marker {
            t.append(relay ?? "")
            t.append(marker.rawValue)
            if let pubkey {
                t.append(pubkey.hex())
            }
        } else if let relay {
            t.append(relay)
        }
        return t
    }

    /// Parses a NoteRef from a tag per NIP-10: `["e", <event-id>, <relay-url>, <marker>, <pubkey>]`
    /// Only parses pubkey from position 4 when a valid marker is present in position 3.
    static func from_tag(tag: TagSequence) -> NoteRef? {
        guard tag.count >= 2 else { return nil }

        var i = tag.makeIterator()

        guard let t0 = i.next(),
              t0.single_char == "e",
              let t1 = i.next(),
              let note_id = t1.id().map(NoteId.init)
        else {
            return nil
        }

        var relay: String? = nil
        var marker: Marker? = nil
        var pubkey: Pubkey? = nil

        if tag.count >= 3, let r = i.next() {
            relay = r.string()
            if tag.count >= 4, let m = i.next() {
                marker = Marker(m)
                // Only parse pubkey when marker is recognized per NIP-10
                if marker != nil, tag.count >= 5, let pk = i.next(), let pubkeyData = pk.id() {
                    pubkey = Pubkey(pubkeyData)
                }
            }
        }

        return NoteRef(note_id: note_id, relay: relay, marker: marker, pubkey: pubkey)
    }
}
