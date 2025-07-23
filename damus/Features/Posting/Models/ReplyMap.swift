//
//  ReplyMap.swift
//  damus
//
//  Created by William Casarin on 2022-04-19.
//

import Foundation

class ReplyMap {
    var replies: [NoteId: Set<NoteId>] = [:]

    func lookup(_ id: NoteId) -> Set<NoteId>? {
        return replies[id]
    }
    
    private func ensure_set(id: NoteId) {
        if replies[id] == nil {
            replies[id] = Set()
        }
    }
    
    @discardableResult
    func add(id: NoteId, reply_id: NoteId) -> Bool {
        ensure_set(id: id)
        if (replies[id]!).contains(reply_id) {
            return false
        }
        replies[id]!.insert(reply_id)
        return true
    }
}
