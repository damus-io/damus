//
//  Keys.swift
//  damus
//
//  Created by William Casarin on 2022-05-21.
//

import Foundation
import secp256k1

struct Keypair {
    let pubkey: String
    let privkey: String
}

func generate_new_keypair() -> Keypair {
    let key = try! secp256k1.Signing.PrivateKey()
    let privkey = hex_encode(key.rawRepresentation)
    let pubkey = hex_encode(Data(key.publicKey.xonlyKeyBytes))
    print("generating privkey:\(privkey) pubkey:\(pubkey)")
    return Keypair(pubkey: pubkey, privkey: privkey)
}

func save_keypair(pubkey: String, privkey: String) {
    UserDefaults.standard.set(pubkey, forKey: "pubkey")
    UserDefaults.standard.set(privkey, forKey: "privkey")
}

func get_saved_keypair() -> Keypair? {
    get_saved_pubkey().flatMap { pubkey in
        get_saved_privkey().map { privkey in
            return Keypair(pubkey: pubkey, privkey: privkey)
        }
    }
}

func get_saved_pubkey() -> String? {
    return UserDefaults.standard.string(forKey: "pubkey")
}

func get_saved_privkey() -> String? {
    return UserDefaults.standard.string(forKey: "privkey")
}
