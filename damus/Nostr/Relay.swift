//
//  Relay.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation

struct RelayInfo: Codable {
    let read: Bool
    let write: Bool

    static let rw = RelayInfo(read: true, write: true)
}

struct RelayDescriptor: Codable {
    let url: URL
    let info: RelayInfo
}

struct Relay: Identifiable {
    let descriptor: RelayDescriptor
    let connection: RelayConnection

    var id: String {
        return get_relay_id(descriptor.url)
    }

}

enum RelayError: Error {
    case RelayAlreadyExists
    case RelayNotFound
}

func get_relay_id(_ url: URL) -> String {
    return url.absoluteString
}
