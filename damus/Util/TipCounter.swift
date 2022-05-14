//
//  TipCounter.swift
//  damus
//
//  Created by William Casarin on 2022-05-11.
//

import Foundation

class TipCounter {
    var tips: [String: Int64] = [:]
    var user_tips: [String: Set<String>] = [:]
    var our_tips: [String: NostrEvent] = [:]
    var our_pubkey: String
    
    enum CountResult {
        case already_tipped
        case success(Int64)
    }
    
    init (our_pubkey: String) {
        self.our_pubkey = our_pubkey
    }
}
    
