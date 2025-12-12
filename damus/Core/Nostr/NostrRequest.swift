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
    /// Negentropy open
    case negentropyOpen(subscriptionId: String, filters: [NostrFilter], initialMessage: [UInt8])
    /// Negentropy message
    case negentropyMessage(subscriptionId: String, message: [UInt8])
    /// Close negentropy communication
    case negentropyClose(subscriptionId: String)

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
        case .negentropyOpen:
            return false
        case .negentropyMessage:
            return false
        case .negentropyClose:
            return false
        }
    }
    
    /// Whether this request is meant to read data from a relay
    var is_read: Bool {
        return !is_write
    }
    
}
