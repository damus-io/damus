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

public struct RelayDescriptor {
    public let url: RelayURL
    public let info: RelayInfo
}

enum RelayFlags: Int {
    case none = 0
    case broken = 1
}

struct Limitations: Codable {
    let payment_required: Bool?
    
    static var empty: Limitations {
        Limitations(payment_required: nil)
    }
}

struct RelayMetadata: Codable {
    let name: String?
    let description: String?
    let pubkey: String?
    let contact: String?
    let supported_nips: [Int]?
    let software: String?
    let version: String?
    let limitation: Limitations?
    let payments_url: String?
    
    var is_paid: Bool {
        return limitation?.payment_required ?? false
    }
}

class Relay: Identifiable {
    let descriptor: RelayDescriptor
    let connection: RelayConnection
    
    var flags: Int
    
    init(descriptor: RelayDescriptor, connection: RelayConnection) {
        self.flags = 0
        self.descriptor = descriptor
        self.connection = connection
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
}

func get_relay_id(_ url: RelayURL) -> String {
    return url.url.absoluteString
}
