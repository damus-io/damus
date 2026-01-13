//
//  NostrRequest.swift
//  damus
//
//  Created by William Casarin on 2022-04-12.
//

import Foundation

struct NostrSubscribe {
    let filters: [NostrFilter]
    let sub_id: String
}

/// Models a request/message that is sent to a Nostr relay
enum NostrRequestType {
    /// A standard nostr request
    case typical(NostrRequest)
    /// A customized nostr request. Generally used in the context of a nostrscript.
    case custom(String)
    
    /// Whether this request is meant to write data to a relay
    var is_write: Bool {
        guard case .typical(let req) = self else {
            return true
        }
        
        return req.is_write
    }
    
    /// Whether this request is meant to read data from a relay
    var is_read: Bool {
        guard case .typical(let req) = self else {
            return true
        }

        return req.is_read
    }
}

extension NostrRequestType {
    /// Profile-related kinds that should be queried on profiles-only relays
    static let profileKinds: Set<NostrKind> = [.metadata, .contacts, .relay_list]

    /// Whether this request is for profile-related data only
    var isProfileRelated: Bool {
        guard case .typical(let req) = self else { return false }
        guard case .subscribe(let sub) = req else { return false }

        // Check if ALL filters contain ONLY profile-related kinds
        return sub.filters.allSatisfy { filter in
            guard let kinds = filter.kinds else { return false }  // No kinds specified = could be anything
            return kinds.allSatisfy { Self.profileKinds.contains($0) }
        }
    }
}

/// Models a standard request/message that is sent to a Nostr relay.
enum NostrRequest {
    /// Subscribes to receive information from the relay
    case subscribe(NostrSubscribe)
    /// Unsubscribes from an existing subscription, addressed by its id
    case unsubscribe(String)
    /// Posts an event
    case event(NostrEvent)
    /// Authenticate with the relay
    case auth(NostrEvent)

    /// Whether this request is meant to write data to a relay
    var is_write: Bool {
        switch self {
        case .subscribe:
            return false
        case .unsubscribe:
            return false
        case .event:
            return true
        case .auth:
            return false
        }
    }
    
    /// Whether this request is meant to read data from a relay
    var is_read: Bool {
        return !is_write
    }
    
}
