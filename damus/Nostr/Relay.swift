//
//  Relay.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation

public struct RelayInfo: Codable {
    let read: Bool
    let write: Bool

    static let rw = RelayInfo(read: true, write: true)
}

public struct RelayDescriptor: Codable {
    public let url: URL
    public let info: RelayInfo
}

enum RelayFlags: Int {
    case none = 0
    case broken = 1
}

class Relay: Identifiable {
    let descriptor: RelayDescriptor
    let connection: RelayConnection
    
    var last_pong: UInt32
    var flags: Int
    
    init(descriptor: RelayDescriptor, connection: RelayConnection) {
        self.flags = 0
        self.descriptor = descriptor
        self.connection = connection
        self.last_pong = 0
    }
    
    func mark_broken() {
        flags |= RelayFlags.broken.rawValue
    }
    
    var is_broken: Bool {
        return (flags & RelayFlags.broken.rawValue) == RelayFlags.broken.rawValue
    }
    
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
