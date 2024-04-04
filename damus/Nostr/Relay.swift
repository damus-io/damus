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

enum RelayAuthenticationError {
    /// Only a public key was provided in keypair to sign challenge.
    ///
    /// A private key is required to sign `auth` challenge.
    case no_private_key
    /// No keypair was provided to sign challenge.
    case no_key
}
enum RelayAuthenticationState: Equatable {
    /// No `auth` request has been made from this relay
    case none
    /// We have received an `auth` challenge, but have not yet replied to the challenge
    case pending
    /// We have received an `auth` challenge and replied with an `auth` event
    case verified
    /// We received an `auth` challenge but failed to reply to the challenge
    case error(RelayAuthenticationError)
}

struct Limitations: Codable {
    let payment_required: Bool?
    
    static var empty: Limitations {
        Limitations(payment_required: nil)
    }
}

struct Admission: Codable {
    let amount: Int64
    let unit: String
}

struct Subscription: Codable {
    let amount: Int64
    let unit: String
    let period: Int
}

struct Publication: Codable {
    let kinds: [Int]
    let amount: Int64
    let unit: String
}

struct Fees: Codable {
    let admission: [Admission]?
    let subscription: [Subscription]?
    let publication: [Publication]?
    
    static var empty: Fees {
        Fees(admission: nil, subscription: nil, publication: nil)
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
    let icon: String?
    let fees: Fees?
    
    var is_paid: Bool {
        return limitation?.payment_required ?? false
    }
}

class Relay: Identifiable {
    let descriptor: RelayDescriptor
    let connection: RelayConnection
    var authentication_state: RelayAuthenticationState

    var flags: Int
    
    init(descriptor: RelayDescriptor, connection: RelayConnection) {
        self.flags = 0
        self.descriptor = descriptor
        self.connection = connection
        self.authentication_state = RelayAuthenticationState.none
    }
    
    var is_broken: Bool {
        return (flags & RelayFlags.broken.rawValue) == RelayFlags.broken.rawValue
    }

    var id: RelayURL {
        return descriptor.url
    }

}

enum RelayError: Error {
    case RelayAlreadyExists
}
