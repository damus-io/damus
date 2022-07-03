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
    
    func lookup_or_create(_ pubkey: String) -> DirectMessageModel {
        if let dm = lookup(pubkey) {
            return dm
        }
        
        let new = DirectMessageModel()
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
