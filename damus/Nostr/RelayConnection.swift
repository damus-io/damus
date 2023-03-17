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

final class RelayConnection: WebSocketDelegate {
    enum State {
        case notConnected
        case connecting
        case reconnecting
        case connected
        case failed
    }
    
    private(set) var state: State = .notConnected
    
    private(set) var last_connection_attempt: TimeInterval = 0
    private lazy var socket = {
        let req = URLRequest(url: url)
        let socket = WebSocket(request: req, compressionHandler: .none)
        socket.delegate = self
        return socket
    }()
    private let eventHandler: (NostrConnectionEvent) -> ()
    let url: URL
    
    init(url: URL, eventHandler: @escaping (NostrConnectionEvent) -> ()) {
        self.url = url
        self.eventHandler = eventHandler
    }
    
    func reconnect() {
        if state == .connected {
            state = .reconnecting
            disconnect()
        } else {
            // we're already disconnected, so just connect
            connect()
        }
    }
    
    func connect(force: Bool = false) {
        if !force && (state == .connected || state == .connecting) {
            return
        }
        
        state = .connecting
        last_connection_attempt = Date().timeIntervalSince1970
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
    
    private func decodeEvent(_ txt: String) throws -> NostrConnectionEvent {
        if let ev = decode_nostr_event(txt: txt) {
            return .nostr_event(ev)
        } else {
            throw DecodingError.dataCorrupted(.init(codingPath: [], debugDescription: "decoding event failed"))
        }
    }
    
    @MainActor
    private func handleEvent(_ event: NostrConnectionEvent) async {
        eventHandler(event)
    }
    
    // MARK: - WebSocketDelegate
    
    func didReceive(event: WebSocketEvent, client: WebSocket) {
        switch event {
        case .connected:
            state = .connected

        case .disconnected:
            if state == .reconnecting {
                connect()
            } else {
                state = .notConnected
            }

        case .cancelled, .error:
            state = .failed

        case .text(let txt):
            Task(priority: .userInitiated) {
                do {
                    let event = try decodeEvent(txt)
                    await handleEvent(event)
                } catch {
                    print("decode failed for \(txt): \(error)")
                    // TODO: trigger event error
                }
            }

        default:
            break
        }

        eventHandler(.ws_event(event))
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
