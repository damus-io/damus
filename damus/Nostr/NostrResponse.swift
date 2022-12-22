//
//  NostrResponse.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation

enum NostrResponse: Decodable {
    case event(String, NostrEvent)
    case notice(String)
    case eose(String)
    
    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        
        // Only use first item
        let typ = try container.decode(String.self)
        
        switch typ {
        case "EVENT":
            let sub_id = try container.decode(String.self)
            var ev: NostrEvent
            do {
                ev = try container.decode(NostrEvent.self)
            } catch {
                print(error)
                throw error
            }
            //ev.pow = count_hash_leading_zero_bits(ev.id)
            self = .event(sub_id, ev)
        case "NOTICE":
            let msg = try container.decode(String.self)
            self = .notice(msg)
        case "EOSE":
            let sub_id = try container.decode(String.self)
            self = .eose(sub_id)
        default:
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "expected EVENT or NOTICE, got \(typ)"))
        }
    }
}

