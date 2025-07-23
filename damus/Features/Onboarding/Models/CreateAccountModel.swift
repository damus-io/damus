//
//  CreateAccountModel.swift
//  damus
//
//  Created by William Casarin on 2022-05-20.
//

import Foundation


class CreateAccountModel: ObservableObject {
    @Published var display_name: String = ""
    @Published var name: String = ""
    @Published var about: String = ""
    @Published var pubkey: Pubkey = .empty
    @Published var privkey: Privkey = .empty
    @Published var profile_image: URL? = nil

    var rendered_name: String {
        if display_name.isEmpty {
            return name
        }
        return display_name
    }
    
    var keypair: Keypair {
        return Keypair(pubkey: self.pubkey, privkey: self.privkey)
    }
    
    var full_keypair: FullKeypair {
        return FullKeypair(pubkey: self.pubkey, privkey: self.privkey)
    }
    
    init(display_name: String = "", name: String = "", about: String = "") {
        let keypair = generate_new_keypair()
        self.pubkey = keypair.pubkey
        self.privkey = keypair.privkey

        self.display_name = display_name
        self.name = name
        self.about = about
    }
}
