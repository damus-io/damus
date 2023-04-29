//
//  RelayBootstrap.swift
//  damus
//
//  Created by William Casarin on 2023-04-04.
//

import Foundation

let BOOTSTRAP_RELAYS = [
    "wss://relay.damus.io",
    "wss://eden.nostr.land",
    "wss://nostr.wine",
    "wss://nos.lol",
]

func bootstrap_relays_setting_key(pubkey: String) -> String {
    return pk_setting_key(pubkey, key: "bootstrap_relays")
}

func save_bootstrap_relays(pubkey: String, relays: [String])  {
    let key = bootstrap_relays_setting_key(pubkey: pubkey)
    
    UserDefaults.standard.set(relays, forKey: key)
}

func load_bootstrap_relays(pubkey: String) -> [String] {
    let key = bootstrap_relays_setting_key(pubkey: pubkey)
    
    guard let relays = UserDefaults.standard.stringArray(forKey: key) else {
        print("loading default bootstrap relays")
        return BOOTSTRAP_RELAYS.map { $0 }
    }
    
    if relays.count == 0 {
        print("loading default bootstrap relays")
        return BOOTSTRAP_RELAYS.map { $0 }
    }
    
    let loaded_relays = Array(Set(relays + BOOTSTRAP_RELAYS))
    print("Loading custom bootstrap relays: \(loaded_relays)")
    return loaded_relays
}

