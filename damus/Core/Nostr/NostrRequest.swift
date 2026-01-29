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
    case negentropyOpen(subscriptionId: String, filter: NostrFilter, initialMessage: [UInt8])
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

func make_nostr_req(_ req: NostrRequest) -> String? {
    switch req {
    case .subscribe(let sub):
        return make_nostr_subscription_req(sub.filters, sub_id: sub.sub_id)
    case .unsubscribe(let sub_id):
        return make_nostr_unsubscribe_req(sub_id)
    case .event(let ev):
        return make_nostr_push_event(ev: ev)
    case .auth(let ev):
        return make_nostr_auth_event(ev: ev)
    case .negentropyOpen(subscriptionId: let subscriptionId, filter: let filter, initialMessage: let initialMessage):
        return make_nostr_negentropy_open_req(subscriptionId: subscriptionId, filter: filter, initialMessage: initialMessage)
    case .negentropyMessage(subscriptionId: let subscriptionId, message: let message):
        return make_nostr_negentropy_message_req(subscriptionId: subscriptionId, message: message)
    case .negentropyClose(subscriptionId: let subscriptionId):
        return make_nostr_negentropy_close_req(subscriptionId: subscriptionId)
    }
}

func make_nostr_auth_event(ev: NostrEvent) -> String? {
    guard let event = encode_json(ev) else {
        return nil
    }
    let encoded = "[\"AUTH\",\(event)]"
    print(encoded)
    return encoded
}

func make_nostr_push_event(ev: NostrEvent) -> String? {
    guard let event = encode_json(ev) else {
        return nil
    }
    let encoded = "[\"EVENT\",\(event)]"
    print(encoded)
    return encoded
}

func make_nostr_unsubscribe_req(_ sub_id: String) -> String? {
    "[\"CLOSE\",\"\(sub_id)\"]"
}

func make_nostr_subscription_req(_ filters: [NostrFilter], sub_id: String) -> String? {
    let encoder = JSONEncoder()
    var req = "[\"REQ\",\"\(sub_id)\""
    for filter in filters {
        req += ","
        guard let filter_json = try? encoder.encode(filter) else {
            return nil
        }
        let filter_json_str = String(decoding: filter_json, as: UTF8.self)
        req += filter_json_str
    }
    req += "]"
    return req
}

func make_nostr_negentropy_open_req(subscriptionId: String, filter: NostrFilter, initialMessage: [UInt8]) -> String? {
    let encoder = JSONEncoder()
    let messageData = Data(initialMessage)
    let messageHex = hex_encode(messageData)
    var req = "[\"NEG-OPEN\",\"\(subscriptionId)\","
    guard let filter_json = try? encoder.encode(filter) else {
        return nil
    }
    let filter_json_str = String(decoding: filter_json, as: UTF8.self)
    req += filter_json_str
    req += ",\"\(messageHex)\""
    req += "]"
    return req
}

func make_nostr_negentropy_message_req(subscriptionId: String, message: [UInt8]) -> String? {
    let messageData = Data(message)
    let messageHex = hex_encode(messageData)
    return "[\"NEG-MSG\",\"\(subscriptionId)\",\"\(messageHex)\"]"
}

func make_nostr_negentropy_close_req(subscriptionId: String) -> String? {
    return "[\"NEG-CLOSE\",\"\(subscriptionId)\"]"
}

