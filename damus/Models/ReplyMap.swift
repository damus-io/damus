//
//  ReplyMap.swift
//  damus
//
//  Created by William Casarin on 2022-04-19.
//

import Foundation

class ReplyMap {
    var replies: [String: String] = [:]
    
    func lookup(_ id: String) -> String? {
        return replies[id]
    }
    func add(id: String, reply_id: String) {
        replies[id] = reply_id
    }
}
