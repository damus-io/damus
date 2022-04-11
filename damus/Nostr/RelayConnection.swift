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

