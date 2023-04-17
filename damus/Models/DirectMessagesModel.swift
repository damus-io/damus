//
//  DirectMessagesModel.swift
//  damus
//
//  Created by William Casarin on 2022-06-29.
//

import Foundation

class DirectMessagesModel: ObservableObject {
    @Published var dms: [DirectMessageModel] = []
    @Published var loading: Bool = false
    @Published var open_dm: Bool = false
    @Published private(set) var active_model: DirectMessageModel = DirectMessageModel(our_pubkey: "", pubkey: "")
    let our_pubkey: String
    
    init(our_pubkey: String) {
        self.our_pubkey = our_pubkey
    }
    
    var message_requests: [DirectMessageModel] {
        return dms.filter { dm in dm.is_request }
    }
    
    var friend_dms: [DirectMessageModel] {
        return dms.filter { dm in !dm.is_request }
    }

    func set_active_dm_model(_ model: DirectMessageModel) {
        self.active_model = model
    }
    
    func open_dm_by_pk(_ pubkey: String) {
        self.set_active_dm(pubkey)
        self.open_dm = true
    }
    
    func open_dm_by_model(_ model: DirectMessageModel) {
        self.set_active_dm_model(model)
        self.open_dm = true
    }
    
    func set_active_dm(_ pubkey: String) {
        for model in self.dms where model.pubkey == pubkey {
            self.set_active_dm_model(model)
            break
        }
    }
    
    func lookup_or_create(_ pubkey: String) -> DirectMessageModel {
        if let dm = lookup(pubkey) {
            return dm
        }
        
        let new = DirectMessageModel(our_pubkey: our_pubkey, pubkey: pubkey)
        dms.append(new)
        return new
    }
    
    func lookup(_ pubkey: String) -> DirectMessageModel? {
        for dm in dms {
            if pubkey == dm.pubkey {
                return dm
            }
        }
        
        return nil
    }
}
