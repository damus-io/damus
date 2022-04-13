//
//  NostrConnection.swift
//  damus
//
//  Created by William Casarin on 2022-04-02.
//

import Foundation
import Starscream

enum NostrConnectionEvent {
    case ws_event(WebSocketEvent)
    case nostr_event(NostrResponse)
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

    func send(_ req: NostrRequest) {
        guard let req = make_nostr_req(req) else {
            print("failed to encode nostr req: \(req)")
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

func make_nostr_req(_ req: NostrRequest) -> String? {
    switch req {
    case .subscribe(let sub):
        return make_nostr_subscription_req(sub.filters, sub_id: sub.sub_id)
    case .event(let ev):
        return make_nostr_push_event(ev: ev)
    }
}

func make_nostr_push_event(ev: NostrEvent) -> String? {
    let encoder = JSONEncoder()
    let event_data = try! encoder.encode(ev)
    let event = String(decoding: event_data, as: UTF8.self)
    let encoded = "[\"EVENT\",\(event)]"
    print(encoded)
    return encoded
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
    print("req: \(req)")
    return req
}

