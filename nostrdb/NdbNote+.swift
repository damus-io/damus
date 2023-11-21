//
//  NdbNote+.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-11-17.
//

import Foundation

// Extension to make NdbNote compatible with NostrEvent's original API
extension NdbNote {
    private var inner_event: NdbNote? {
        get {
            return NdbNote.owned_from_json_cstr(json: content_raw, json_len: content_len)
        }
    }
    
    func get_inner_event(cache: EventCache) -> NdbNote? {
        guard self.known_kind == .boost else {
            return nil
        }

        if self.content_len == 0, let id = self.referenced_ids.first {
            // TODO: raw id cache lookups
            return cache.lookup(id)
        }

        return self.inner_event
    }
}
