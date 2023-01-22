//
//  DirectMessagesModel.swift
//  damus
//
//  Created by William Casarin on 2022-06-29.
//

import Foundation

class DirectMessagesModel: ObservableObject {
    @Published var dms: [(String, DirectMessageModel)] = []
    @Published var loading: Bool = false
    let our_pubkey: String
    
    init(our_pubkey: String) {
        self.our_pubkey = our_pubkey
    }
    
    var message_requests: [(String, DirectMessageModel)] {
        return dms.filter { dm in dm.1.is_request }
    }
    
    var friend_dms: [(String, DirectMessageModel)] {
        return dms.filter { dm in !dm.1.is_request }
    }
    
    func lookup_or_create(_ pubkey: String) -> DirectMessageModel {
        if let dm = lookup(pubkey) {
            return dm
        }
        
        let new = DirectMessageModel(our_pubkey: our_pubkey)
        dms.append((pubkey, new))
        return new
    }
    
    func lookup(_ pubkey: String) -> DirectMessageModel? {
        for dm in dms {
            if pubkey == dm.0 {
                return dm.1
            }
        }
        
        return nil
    }
}
