//
//  Relay.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation

public struct RelayInfo: Codable {
    let read: Bool?
    let write: Bool?
    
    init(read: Bool, write: Bool) {
        self.read = read
        self.write = write
    }

    static let rw = RelayInfo(read: true, write: true)
}

enum RelayVariant {
    case regular
    case ephemeral
    case nwc
}

public struct RelayDescriptor {
    let url: RelayURL
    let info: RelayInfo
    let variant: RelayVariant
    
    init(url: RelayURL, info: RelayInfo, variant: RelayVariant = .regular) {
        self.url = url
        self.info = info
        self.variant = variant
    }
    
    var ephemeral: Bool {
        switch variant {
        case .regular:
            return false
        case .ephemeral:
            return true
        case .nwc:
            return true
        }
    }
    
    static func nwc(url: RelayURL) -> RelayDescriptor {
        return RelayDescriptor(url: url, info: .rw, variant: .nwc)
    }
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
    let pubkey: Pubkey?
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
