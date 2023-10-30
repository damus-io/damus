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

let REGION_SPECIFIC_BOOTSTRAP_RELAYS: [Locale.Region: [String]] = [
    Locale.Region.japan: [
        "wss://relay-jp.nostr.wirednet.jp",
        "wss://yabu.me",
        "wss://r.kojira.io",
    ]
]

func bootstrap_relays_setting_key(pubkey: Pubkey) -> String {
    return pk_setting_key(pubkey, key: "bootstrap_relays")
}

func save_bootstrap_relays(pubkey: Pubkey, relays: [String])  {
    let key = bootstrap_relays_setting_key(pubkey: pubkey)
    
    UserDefaults.standard.set(relays, forKey: key)
}

func load_bootstrap_relays(pubkey: Pubkey) -> [String] {
    let key = bootstrap_relays_setting_key(pubkey: pubkey)
    
    guard let relays = UserDefaults.standard.stringArray(forKey: key) else {
        print("loading default bootstrap relays")
        return get_default_bootstrap_relays().map { $0 }
    }
    
    if relays.count == 0 {
        print("loading default bootstrap relays")
        return get_default_bootstrap_relays().map { $0 }
    }
    
    let loaded_relays = Array(Set(relays + get_default_bootstrap_relays()))
    print("Loading custom bootstrap relays: \(loaded_relays)")
    return loaded_relays
}

func get_default_bootstrap_relays() -> [String] {
    var default_bootstrap_relays = BOOTSTRAP_RELAYS
    
    if let user_region = Locale.current.region, let regional_bootstrap_relays = REGION_SPECIFIC_BOOTSTRAP_RELAYS[user_region] {
        default_bootstrap_relays.append(contentsOf: regional_bootstrap_relays)
    }
    
    return default_bootstrap_relays
}
