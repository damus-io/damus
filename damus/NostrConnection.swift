//
//  NostrConnection.swift
//  damus
//
//  Created by William Casarin on 2022-04-02.
//

import Foundation
import Starscream

struct OtherEvent {
    let event_id: String
    let relay_url: String
}

struct KeyEvent {
    let key: String
    let relay_url: String
}

enum NostrConnectionEvent {
    case ws_event(WebSocketEvent)
    case nostr_event(NostrResponse)
}

enum NostrTag {
    case other_event(OtherEvent)
    case key_event(KeyEvent)
}

struct NostrSubscription {
    let sub_id: String
    let filter: NostrFilter
}

struct NostrFilter: Codable {
    let ids: [String]?
    let kinds: [String]?
    let event_ids: [String]?
    let pubkeys: [String]?
    let since: Int64?
    let until: Int64?
    let authors: [String]?

    private enum CodingKeys : String, CodingKey {
        case ids
        case kinds
        case event_ids = "#e"
        case pubkeys = "#p"
        case since
        case until
        case authors
    }
    
    public static func filter_since(_ val: Int64) -> NostrFilter {
        return NostrFilter(ids: nil, kinds: nil, event_ids: nil, pubkeys: nil, since: val, until: nil, authors: nil)
    }
}

enum NostrResponse: Decodable {
    case event(String, NostrEvent)
    case notice(String)
    
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
            self = .event(sub_id, ev)
            return
        } else if typ == "NOTICE" {
            let msg = try container.decode(String.self)
            self = .notice(msg)
            return
        }
        
        throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "expected EVENT or NOTICE, got \(typ)"))
    }
}

struct NostrEvent: Decodable, Identifiable {
    let id: String
    let pubkey: String
    let created_at: Int64
    let kind: Int
    let tags: [[String]]
    let content: String
    let sig: String
}

class NostrConnection: WebSocketDelegate {
    var isConnected: Bool = false
    var socket: WebSocket
    var handleEvent: (NostrConnectionEvent) -> ()
    
    init(url: URL, handleEvent: @escaping (NostrConnectionEvent) -> ()) {
        var req = URLRequest(url: url)
        req.timeoutInterval = 5
        self.socket = WebSocket(request: req)
        self.handleEvent = handleEvent
        
        socket.delegate = self
    }
    
    func connect(){
        socket.connect()
    }
    
    func disconnect() {
        socket.disconnect()
    }
    
    func send(_ filter: NostrFilter, sub_id: String) {
        guard let req = make_nostr_req(filter, sub_id: sub_id) else {
            print("failed to encode nostr req: \(filter)")
            return
        }
        socket.write(string: req)
    }
    
    func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .connected:
            self.isConnected = true
            
        case .disconnected: fallthrough
        case .cancelled: fallthrough
        case .error:
            self.isConnected = false
            
        case .text(let txt):
            if let ev = decode_nostr_event(txt: txt) {
                handleEvent(.nostr_event(ev))
                return
            }
            
            print("decode failed for \(txt)")
            // TODO: trigger event error
            
        default:
            break
        }
        
        handleEvent(.ws_event(event))
    }
    
}

func decode_nostr_event(txt: String) -> NostrResponse? {
    return decode_data(Data(txt.utf8))
}

func decode_data<T: Decodable>(_ data: Data) -> T? {
    let decoder = JSONDecoder()
    do {
        return try decoder.decode(T.self, from: data)
    } catch {
        print("decode_data failed for \(T.self): \(error)")
    }

    return nil
}

func make_nostr_req(_ filter: NostrFilter, sub_id: String) -> String? {
    let encoder = JSONEncoder()
    guard let filter_json = try? encoder.encode(filter) else {
        return nil
    }
    let filter_json_str = String(decoding: filter_json, as: UTF8.self)
    return "[\"REQ\",\"\(sub_id)\",\(filter_json_str)]"
}

