//
//  NdbNote+.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-11-17.
//

import Foundation

// Extension to make NdbNote compatible with NostrEvent's original API
extension NdbNote {
    func parse_inner_event() -> NdbNote? {
        return NdbNote.owned_from_json_cstr(json: content_raw, json_len: content_len)
    }

    func get_cached_inner_event(cache: EventCache) -> NdbNote? {
        guard self.known_kind == .boost || self.known_kind == .highlight else {
            return nil
        }

        if self.content_len == 0, let id = self.referenced_ids.first {
            // TODO: raw id cache lookups
            return cache.lookup(id)
        }

        return nil
    }

    func get_inner_event(cache: EventCache) -> NdbNote? {
        if let ev = get_cached_inner_event(cache: cache) {
            return ev
        }
        return self.parse_inner_event()
    }

    /// Returns the target event ID and relay hints for a repost (kind 6) event.
    ///
    /// Per NIP-18, reposts MUST include an `e` tag with the reposted event's ID,
    /// and the tag MUST include a relay URL as its third entry.
    ///
    /// - Returns: A tuple of (noteId, relayHints) if this is a repost with a valid e tag, nil otherwise.
    func repostTarget() -> (noteId: NoteId, relayHints: [RelayURL])? {
        guard self.known_kind == .boost else { return nil }

        for tag in self.tags {
            guard tag.count >= 2 else { continue }
            guard tag[0].matches_char("e") else { continue }
            guard let noteIdData = tag[1].id() else { continue }

            let noteId = NoteId(noteIdData)
            let relayHints = tag.relayHints
            return (noteId, relayHints)
        }

        return nil
    }
}
