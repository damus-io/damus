//
//  NdbNote+.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-11-17.
//

import Foundation

// Extension to make NdbNote compatible with NostrEvent's original API
extension NdbNote {
    /// Decode through the shared verifier; voice wrappers cannot bypass attribution checks.
    func parse_inner_event() -> NdbNote? {
        get_inner_event()
    }

    /// Reuse an original already verified during background voice-event loading.
    func get_cached_inner_event(cache: EventCache) -> NdbNote? {
        if known_kind == .voice_repost { return cached_voice_original }
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

    /// Return the original id and relay hints for a text or voice repost.
    /// Voice wrappers require both signatures; call off the main thread.
    func repostTarget() -> (noteId: NoteId, relayHints: [RelayURL])? {
        guard known_kind?.isRepost == true else { return nil }
        if known_kind == .voice_repost && !verify_voice_repost() { return nil }

        for tag in self.tags {
            guard tag.count >= 2 else { continue }
            guard tag[0].matches_char("e") else { continue }
            if known_kind == .voice_repost, tag.count >= 5, tag[4].matches_str("repost-source") { continue }
            guard let noteIdData = tag[1].id() else { continue }

            let noteId = NoteId(noteIdData)
            let relayHints = tag.relayHints
            return (noteId, relayHints)
        }

        return nil
    }
}
