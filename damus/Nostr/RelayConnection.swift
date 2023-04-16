//
//  NostrConnection.swift
//  damus
//
//  Created by William Casarin on 2022-04-02.
//

import Combine
import Foundation

enum NostrConnectionEvent {
    case ws_event(WebSocketEvent)
    case nostr_event(NostrResponse)
}

final class RelayConnection {
    private(set) var isConnected = false
    private(set) var isConnecting = false
    
    private(set) var last_connection_attempt: TimeInterval = 0
    private lazy var socket = WebSocket(url)
    private var subscriptionToken: AnyCancellable?
    
    private var handleEvent: (NostrConnectionEvent) -> ()
    private let url: URL

    init(url: URL, handleEvent: @escaping (NostrConnectionEvent) -> ()) {
        self.url = url
        self.handleEvent = handleEvent
    }
    
    func connect(force: Bool = false) {
        if !force && (isConnected || isConnecting) {
            return
        }
        
        isConnecting = true
        last_connection_attempt = Date().timeIntervalSince1970
        
        subscriptionToken = socket.subject
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                switch completion {
                case .failure(let error):
                    self?.receive(event: .error(error))
                case .finished:
                    self?.receive(event: .disconnected(.normalClosure, nil))
                }
            } receiveValue: { [weak self] event in
                self?.receive(event: event)
            }
            
        socket.connect()
    }

    func disconnect() {
        socket.disconnect()
        subscriptionToken = nil
        
        isConnected = false
        isConnecting = false
    }

    func send(_ req: NostrRequest) {
        guard let req = make_nostr_req(req) else {
            print("failed to encode nostr req: \(req)")
            return
        }
        socket.send(.string(req))
    }
    
    private func receive(event: WebSocketEvent) {
        switch event {
        case .connected:
            self.isConnected = true
            self.isConnecting = false
        case .message(let message):
            self.receive(message: message)
        case .disconnected(let closeCode, let reason):
            if closeCode != .normalClosure {
                print("⚠️ Warning: RelayConnection (\(self.url)) closed with code \(closeCode), reason: \(String(describing: reason))")
            }
            reconnect()
        case .error(let error):
            print("⚠️ Warning: RelayConnection (\(self.url)) error: \(error)")
            reconnect()
        }
        self.handleEvent(.ws_event(event))
    }
    
    func reconnect() {
        guard !isConnecting else {
            return  // we're already trying to connect
        }
        disconnect()
        connect()
    }
    
    private func receive(message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let messageString):
            if messageString.utf8.count > 2000 {
                DispatchQueue.global(qos: .default).async {
                    if let ev = decode_nostr_event(txt: messageString) {
                        DispatchQueue.main.async {
                            self.handleEvent(.nostr_event(ev))
                        }
                        return
                    }
                }
            } else {
                if let ev = decode_nostr_event(txt: messageString) {
                    handleEvent(.nostr_event(ev))
                    return
                }
            }
        case .data(let messageData):
            if let messageString = String(data: messageData, encoding: .utf8) {
                receive(message: .string(messageString))
            }
        @unknown default:
            print("An unexpected URLSessionWebSocketTask.Message was received.")
        }
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
