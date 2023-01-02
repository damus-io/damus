//
//  Constants.swift
//  damus
//
//  Created by Sam DuBois on 12/18/22.
//

import Foundation

public class Constants {
    
    static let PUB_KEY = "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"
    
    static let EXAMPLE_DEMOS: DamusState = .empty
    
    static let EXAMPLE_EVENTS = [
        NostrEvent(id: UUID().description, content: "Nostr - Damus... Haha get it? Bonjour Le Monde mon Ami! C'est la tres importante", pubkey: "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"),
        NostrEvent(id: UUID().description, content: "This is a test for a really long note that somebody sent because they thought they were super cool or maybe they were just really excited to share something with the world.", pubkey: "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"),
        NostrEvent(id: UUID().description, content: "Bonjour Le Monde", pubkey: "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"),
        NostrEvent(id: UUID().description, content: "Why am I helping on this app? Because it's fun!", pubkey: "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"),
        NostrEvent(id: UUID().description, content: "Pizza and Icecream! Pizza and Icecream! Testing Testing! 1 .. 2.. 3..", pubkey: "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"),
        NostrEvent(id: UUID().description, content: "Hello World! This is so cool!", pubkey: "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"),
        NostrEvent(id: UUID().description, content: "Nostr - Damus... Haha get it?", pubkey: "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"),
        NostrEvent(id: UUID().description, content: "Hello World! This is so cool!", pubkey: "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"),
        NostrEvent(id: UUID().description, content: "Bonjour Le Monde", pubkey: "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"),
    ]
}
