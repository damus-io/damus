//
//  RelayBootstrap.swift
//  damus
//
//  Created by William Casarin on 2023-04-04.
//

import Foundation

// This is `fileprivate` because external code should use the `get_default_bootstrap_relays` instead.
fileprivate let BOOTSTRAP_RELAYS = [
    "wss://relay.damus.io",
    "wss://eden.nostr.land",
    "wss://nostr.wine",
    "wss://nos.lol",
]


fileprivate enum TmpRegion: String, Hashable {
    case japan = "JP"
    case thailand = "TH"
    case germany = "DE"
}

fileprivate let REGION_SPECIFIC_BOOTSTRAP_RELAYS: [TmpRegion: [String]] = [
    TmpRegion.japan: [
        "wss://relay-jp.nostr.wirednet.jp",
        "wss://yabu.me",
        "wss://r.kojira.io",
    ],
    TmpRegion.thailand: [
        "wss://relay.siamstr.com",
        "wss://relay.zerosatoshi.xyz",
        "wss://th2.nostr.earnkrub.xyz",
    ],
    TmpRegion.germany: [
        "wss://nostr.einundzwanzig.space",
        "wss://nostr.cercatrova.me",
        "wss://nostr.bitcoinplebs.de",
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
    
    if let user_region = TmpRegion(rawValue: Locale.current.identifier), let regional_bootstrap_relays = REGION_SPECIFIC_BOOTSTRAP_RELAYS[user_region] {
        default_bootstrap_relays.append(contentsOf: regional_bootstrap_relays)
    }
    
    return default_bootstrap_relays
}
