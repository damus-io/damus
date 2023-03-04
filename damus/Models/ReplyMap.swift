//
//  ReplyMap.swift
//  damus
//
//  Created by William Casarin on 2022-04-19.
//

import Foundation

class ReplyMap {
    var replies: [String: Set<String>] = [:]
    
    func lookup(_ id: String) -> Set<String>? {
        return replies[id]
    }
    
    private func ensure_set(id: String) {
        if replies[id] == nil {
            replies[id] = Set()
        }
    }
    
    @discardableResult
    func add(id: String, reply_id: String) -> Bool {
        ensure_set(id: id)
        if (replies[id]!).contains(reply_id) {
            return false
        }
        replies[id]!.insert(reply_id)
        return true
    }
}
