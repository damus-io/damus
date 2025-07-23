//
//  DirectMessageModel.swift
//  damus
//
//  Created by William Casarin on 2022-07-03.
//

import Foundation

class DirectMessageModel: ObservableObject {
    @Published var events: [NostrEvent] {
        didSet {
            is_request = determine_is_request()
        }
    }

    @Published var draft: String = ""
    
    let pubkey: Pubkey

    var is_request = false
    var our_pubkey: Pubkey

    func determine_is_request() -> Bool {
        for event in events {
            if event.pubkey == our_pubkey {
                return false
            }
        }
        
        return true
    }
    
    init(events: [NostrEvent] = [], our_pubkey: Pubkey, pubkey: Pubkey) {
        self.events = events
        self.our_pubkey = our_pubkey
        self.pubkey = pubkey
    }
}
