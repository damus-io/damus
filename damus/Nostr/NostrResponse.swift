//
//  NostrResponse.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation

struct CommandResult {
    let event_id: String
    let ok: Bool
    let msg: String
}

enum NostrResponse: Decodable {
    case event(String, NostrEvent)
    case notice(String)
    case eose(String)
    case ok(CommandResult)
    
    var subid: String? {
        switch self {
        case .ok(_):
            return nil
        case .event(let sub_id, _):
            return sub_id
        case .eose(let sub_id):
            return sub_id
        case .notice:
            return nil
        }
    }

    init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()

        // Only use first item
        let typ = try container.decode(String.self)
        if typ == "EVENT" {
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
            return
        } else if typ == "NOTICE" {
            let msg = try container.decode(String.self)
            self = .notice(msg)
            return
        } else if typ == "EOSE" {
            let sub_id = try container.decode(String.self)
            self = .eose(sub_id)
            return
        } else if typ == "OK" {
            var cr: CommandResult
            do {
                let event_id = try container.decode(String.self)
                let ok = try container.decode(Bool.self)
                let msg = try container.decode(String.self)
                cr = CommandResult(event_id: event_id, ok: ok, msg: msg)
            } catch {
                print(error)
                throw error
            }
            self = .ok(cr)
            return
            //ev.pow = count_hash_leading_zero_bits(ev.id)
        }

        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "expected EVENT, NOTICE or OK, got \(typ)"))
    }
}

