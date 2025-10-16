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
    case dmSeal = 13
    case dmChat17 = 14
    case dmFile17 = 15
    case delete = 5
    case boost = 6
    case like = 7
    case chat = 42
    case dmGiftWrap = 1059
    case mute_list = 10000
    case relay_list = 10002
    case dmRelayPreferences = 10050
    case interest_list = 10015
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
    case contact_card = 30_382
    case follow_list = 39089
}

extension NostrKind {
    var isDirectMessage: Bool {
        switch self {
        case .dm, .dmChat17, .dmFile17:
            return true
        default:
            return false
        }
    }

    var isGiftWrappedMessage: Bool {
        self == .dmGiftWrap
    }
}
