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
    var isConnecting: Bool = false
    var isReconnecting: Bool = false
    var last_connection_attempt: Double = 0
    var socket: WebSocket
    var handleEvent: (NostrConnectionEvent) -> ()
    let url: URL

    init(url: URL, handleEvent: @escaping (NostrConnectionEvent) -> ()) {
        self.url = url
        self.handleEvent = handleEvent
        // just init, we don't actually use this one
        self.socket = make_websocket(url: url)
    }
    
    func reconnect() {
        if self.isConnected {
            self.isReconnecting = true
            self.disconnect()
        } else {
            // we're already disconnected, so just connect
            self.connect(force: true)
        }
    }

    func connect(force: Bool = false){
        if !force && (self.isConnected || self.isConnecting) {
            return
        }

        var req = URLRequest(url: self.url)
        req.timeoutInterval = 5
        socket = make_websocket(url: url)
        socket.delegate = self

        isConnecting = true
        last_connection_attempt = Date().timeIntervalSince1970
        socket.connect()
    }

    func disconnect() {
        socket.disconnect()
        isConnected = false
        isConnecting = false
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
            self.isConnecting = false

        case .disconnected:
            self.isConnecting = false
            self.isConnected = false
            if self.isReconnecting {
                self.isReconnecting = false
                self.connect()
            }

        case .cancelled: fallthrough
        case .error:
            self.isConnecting = false
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
    case .unsubscribe(let sub_id):
        return make_nostr_unsubscribe_req(sub_id)
    case .event(let ev):
        return make_nostr_push_event(ev: ev)
    }
}

func make_nostr_push_event(ev: NostrEvent) -> String? {
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    let event_data = try! encoder.encode(ev)
    let event = String(decoding: event_data, as: UTF8.self)
    let encoded = "[\"EVENT\",\(event)]"
    print(encoded)
    return encoded
}

func make_nostr_unsubscribe_req(_ sub_id: String) -> String? {
    return "[\"CLOSE\",\"\(sub_id)\"]"
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

func make_websocket(url: URL) -> WebSocket {
    let req = URLRequest(url: url)
    //req.setValue("chat,superchat", forHTTPHeaderField: "Sec-WebSocket-Protocol")
    return WebSocket(request: req, compressionHandler: .none)
}

