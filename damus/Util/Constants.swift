//
//  Constants.swift
//  damus
//
//  Created by Sam DuBois on 12/18/22.
//

import Foundation

public class Constants {
    
    static let PUB_KEY = "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"
    
    static let EXAMPLE_DEMOS = DamusState(pool: RelayPool(), keypair: Keypair(pubkey: PUB_KEY, privkey: "privkey"), likes: EventCounter(our_pubkey: PUB_KEY), boosts: EventCounter(our_pubkey: PUB_KEY), contacts: Contacts(), tips: TipCounter(our_pubkey: PUB_KEY), profiles: Profiles(), dms: DirectMessagesModel())
    
    static let EXAMPLE_EVENTS = [
        NostrEvent(content: "Icecream", pubkey: "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"),
        NostrEvent(content: "This is a test for a really long note that somebody sent because they thought they were super cool or maybe they were just really excited to share something with the world.", pubkey: "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"),
        NostrEvent(content: "Bonjour Le Monde", pubkey: "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"),
        NostrEvent(content: "Why am I helping on this app? Because it's fun!", pubkey: "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"),
        NostrEvent(content: "PIzza", pubkey: "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"),
        NostrEvent(content: "Hello World! This is so cool!", pubkey: "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"),
        NostrEvent(content: "Nostr - Damus... Haha get it?", pubkey: "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"),
    ]
    
    static let WALLETS = """
        [
            {"id": 0, "name": "Strike", "link": "strike:lightning", "appStoreLink": "https://apps.apple.com/us/app/strike-bitcoin-payments/id1488724463"},
            {"id": 1, "name": "Cash App", "link": "squarecash://", "appStoreLink": "https://apps.apple.com/us/app/cash-app/id711923939"},
            {"id": 2, "name": "Muun", "link": "muun:", "appStoreLink": "https://apps.apple.com/us/app/muun-wallet/id1482037683"},
            {"id": 3, "name": "Blue Wallet", "link": "bluewallet:lightning", "appStoreLink": "https://apps.apple.com/us/app/bluewallet-bitcoin-wallet/id1376878040"},
            {"id": 4, "name": "Wallet Of Satoshi", "link": "walletofsatoshi:lightning", "appStoreLink": "https://apps.apple.com/us/app/wallet-of-satoshi/id1438599608"},
            {"id": 5, "name": "Breez", "link": "breez:lightning", "appStoreLink": "https://testflight.apple.com/join/wPju2Du7"},
            {"id": 6, "name": "Zebedee", "link": "zebedee:lightning", "appStoreLink": "https://apps.apple.com/us/app/zebedee-wallet/id1484394401"},
            {"id": 7, "name": "Zeus LN", "link": "zeusln:lightning", "appStoreLink": "https://apps.apple.com/us/app/zeus-ln/id1456038895"},
        ]
        """.data(using: .utf8)!
}
