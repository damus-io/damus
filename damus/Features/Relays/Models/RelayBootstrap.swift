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
    "wss://nostr.land",
    "wss://nostr.wine",
    "wss://nos.lol",
    "wss://relay.divine.video",
]

fileprivate let REGION_SPECIFIC_BOOTSTRAP_RELAYS: [Locale.Region: [String]] = [
    Locale.Region.japan: [
        "wss://relay-jp.nostr.wirednet.jp",
        "wss://yabu.me",
        "wss://r.kojira.io",
    ],
    Locale.Region.thailand: [
        "wss://relay.siamstr.com",
        "wss://relay.zerosatoshi.xyz",
        "wss://th2.nostr.earnkrub.xyz",
    ],
    Locale.Region.germany: [
        "wss://nostr.einundzwanzig.space",
        "wss://nostr.cercatrova.me",
        "wss://nostr.bitcoinplebs.de",
    ]
]

func bootstrap_relays_setting_key(pubkey: Pubkey) -> String {
    return pk_setting_key(pubkey, key: "bootstrap_relays")
}

func save_bootstrap_relays(pubkey: Pubkey, relays: [RelayURL])  {
    let key = bootstrap_relays_setting_key(pubkey: pubkey)

    UserDefaults.standard.set(relays.map({ $0.absoluteString }), forKey: key)
}

func load_bootstrap_relays(pubkey: Pubkey) -> [RelayURL] {
    let key = bootstrap_relays_setting_key(pubkey: pubkey)

    guard let relays = UserDefaults.standard.stringArray(forKey: key) else {
        print("loading default bootstrap relays")
        return get_default_bootstrap_relays().map { $0 }
    }
    
    if relays.count == 0 {
        print("loading default bootstrap relays")
        return get_default_bootstrap_relays().map { $0 }
    }

    let relay_urls = relays.compactMap({ RelayURL($0) })

    let loaded_relays = Array(Set(relay_urls))
    print("Loading custom bootstrap relays: \(loaded_relays)")
    return loaded_relays
}

func get_default_bootstrap_relays() -> [RelayURL] {
    var default_bootstrap_relays: [RelayURL] = BOOTSTRAP_RELAYS.compactMap({ RelayURL($0) })

    if let user_region = Locale.current.region, let regional_bootstrap_relays = REGION_SPECIFIC_BOOTSTRAP_RELAYS[user_region] {
        default_bootstrap_relays.append(contentsOf: regional_bootstrap_relays.compactMap({ RelayURL($0) }))
    }

    return default_bootstrap_relays
}
