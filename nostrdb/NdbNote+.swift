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
}
