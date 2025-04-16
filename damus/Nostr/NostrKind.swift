//
//  NostrKind.swift
//  damus
//
//  Created by William Casarin on 2022-04-27.
//

import Foundation


/// A known Nostr event kind, addressable by name, with the actual number assigned by the protocol as the value
enum NostrKind: UInt32, Codable {
    case metadata = 0
    case text = 1
    case contacts = 3
    case dm = 4
    case delete = 5
    case boost = 6
    case like = 7
    case chat = 42
    case mute_list = 10000
    case relay_list = 10002
    case list_deprecated = 30000
    case draft = 31234
    case longform = 30023
    case zap = 9735
    case zap_request = 9734
    case highlight = 9802
    case nwc_request = 23194
    case nwc_response = 23195
    case http_auth = 27235
    case status = 30315
}
