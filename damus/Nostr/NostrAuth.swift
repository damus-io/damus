//
//  NostrAuth.swift
//  damus
//
//  Created by Charlie Fish on 12/18/23.
//

import Foundation

func make_auth_request(keypair: FullKeypair, challenge_string: String, relay: Relay) -> NostrEvent? {
    let tags: [[String]] = [["relay", relay.descriptor.url.absoluteString],["challenge", challenge_string]]
    let event = NostrEvent(content: "", keypair: keypair.to_keypair(), kind: 22242, tags: tags)
    return event
}
