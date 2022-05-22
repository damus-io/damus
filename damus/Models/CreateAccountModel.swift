//
//  CreateAccountModel.swift
//  damus
//
//  Created by William Casarin on 2022-05-20.
//

import Foundation


class CreateAccountModel: ObservableObject {
    @Published var real_name: String = ""
    @Published var nick_name: String = ""
    @Published var about: String = ""
    @Published var pubkey: String = ""
    @Published var privkey: String = ""
    
    var rendered_name: String {
        if real_name.isEmpty {
            return nick_name
        }
        return real_name
    }
    
    var keypair: Keypair {
        return Keypair(pubkey: self.pubkey, privkey: self.privkey)
    }
    
    init() {
        let keypair = generate_new_keypair()
        self.pubkey = keypair.pubkey
        self.privkey = keypair.privkey
    }
    
    init(real: String, nick: String, about: String) {
        let keypair = generate_new_keypair()
        self.pubkey = keypair.pubkey
        self.privkey = keypair.privkey
        
        self.real_name = real
        self.nick_name = nick
        self.about = about
    }
}
