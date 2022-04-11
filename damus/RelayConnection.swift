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
    var ids: [String]?
    var kinds: [Int]?
    var referenced_ids: [String]?
    var pubkeys: [String]?
    var since: Int64?
    var until: Int64?
    var authors: [String]?

    private enum CodingKeys : String, CodingKey {
        case ids
        case kinds
        case referenced_ids = "#e"
        case pubkeys = "#p"
        case since
        case until
        case authors
    }

    public static var filter_text: NostrFilter {
        NostrFilter(ids: nil, kinds: [1], referenced_ids: nil, pubkeys: nil, since: nil, until: nil, authors: nil)
    }

    public static var filter_profiles: NostrFilter {
        return NostrFilter(ids: nil, kinds: [0], referenced_ids: nil, pubkeys: nil, since: nil, until: nil, authors: nil)
    }

    public static func filter_since(_ val: Int64) -> NostrFilter {
        return NostrFilter(ids: nil, kinds: nil, referenced_ids: nil, pubkeys: nil, since: val, until: nil, authors: nil)
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

struct RelayInfo {
    let read: Bool
    let write: Bool

    static let rw = RelayInfo(read: true, write: true)
}

struct Relay: Identifiable {
    let url: URL
    let info: RelayInfo
    let connection: RelayConnection

    var id: String {
        return get_relay_id(url)
    }

}

func get_relay_id(_ url: URL) -> String {
    return url.absoluteString
}

enum RelayError: Error {
    case RelayAlreadyExists
    case RelayNotFound
}

class RelayPool {
    var relays: [Relay] = []
    let custom_handle_event: (String, NostrConnectionEvent) -> ()

    init(handle_event: @escaping (String, NostrConnectionEvent) -> ()) {
        self.custom_handle_event = handle_event
    }

    func add_relay(_ url: URL, info: RelayInfo) throws {
        let relay_id = get_relay_id(url)
        if get_relay(relay_id) != nil {
            throw RelayError.RelayAlreadyExists
        }
        let conn = RelayConnection(url: url) { event in
            self.handle_event(relay_id: relay_id, event: event)
        }
        let relay = Relay(url: url, info: info, connection: conn)
        self.relays.append(relay)
    }

    func connect(to: [String]? = nil) {
        let relays = to.map{ get_relays($0) } ?? self.relays
        for relay in relays {
            relay.connection.connect()
        }
    }

    func send(filters: [NostrFilter], sub_id: String, to: [String]? = nil) {
        let relays = to.map{ get_relays($0) } ?? self.relays

        for relay in relays {
            if relay.connection.isConnected {
                relay.connection.send(filters, sub_id: sub_id)
            }
        }
    }

    func get_relays(_ ids: [String]) -> [Relay] {
        var relays: [Relay] = []

        for id in ids {
            if let relay = get_relay(id) {
                relays.append(relay)
            }
        }

        return relays
    }

    func get_relay(_ id: String) -> Relay? {
        for relay in relays {
            if relay.id == id {
                return relay
            }
        }

        return nil
    }

    func handle_event(relay_id: String, event: NostrConnectionEvent) {
        // handle reconnect logic, etc?
        custom_handle_event(relay_id, event)
    }
}

class RelayConnection: WebSocketDelegate {
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

    func send(_ filters: [NostrFilter], sub_id: String) {
        guard let req = make_nostr_req(filters, sub_id: sub_id) else {
            print("failed to encode nostr req: \(filters)")
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

func make_nostr_req(_ filters: [NostrFilter], sub_id: String) -> String? {
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
    print("req: \(req)")
    return req
}

