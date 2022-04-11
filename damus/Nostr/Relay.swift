//
//  Relay.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation

struct RelayInfo {
    let read: Bool
    let write: Bool

    static let rw = RelayInfo(read: true, write: true)
}

struct Relay: Identifiable {
    let url: URL
    let info: RelayInfo
    let connection: RelayConnection

    var id: String {
        return get_relay_id(url)
    }

}

enum RelayError: Error {
    case RelayAlreadyExists
    case RelayNotFound
}

func get_relay_id(_ url: URL) -> String {
    return url.absoluteString
}
