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

public struct RelayURL: Hashable {
    private(set) var url: URL
    
    var id: String {
        return url.absoluteString
    }
    
    init?(_ str: String) {
        guard let url = URL(string: str) else {
            return nil
        }
        
        guard let scheme = url.scheme else {
            return nil
        }
        
        guard scheme == "ws" || scheme == "wss" else {
            return nil
        }
        
        self.url = url
    }
}

final class RelayConnection: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false
    
    private(set) var last_connection_attempt: TimeInterval = 0
    private(set) var last_pong: Date? = nil
    private(set) var backoff: TimeInterval = 1.0
    private lazy var socket = WebSocket(url.url)
    private var subscriptionToken: AnyCancellable?
    
    private var handleEvent: (NostrConnectionEvent) -> ()
    private let url: RelayURL
    var log: RelayLog?

    init(url: RelayURL, handleEvent: @escaping (NostrConnectionEvent) -> ()) {
        self.url = url
        self.handleEvent = handleEvent
    }
    
    func ping() {
        socket.ping { err in
            if err == nil {
                self.last_pong = .now
                self.log?.add("Successful ping")
            } else {
                print("pong failed, reconnecting \(self.url.id)")
                self.isConnected = false
                self.isConnecting = false
                self.reconnect_with_backoff()
                self.log?.add("Ping failed")
            }
        }
    }
    
    func connect(force: Bool = false) {
        if !force && (isConnected || isConnecting) {
            return
        }
        
        isConnecting = true
        last_connection_attempt = Date().timeIntervalSince1970
        
        subscriptionToken = socket.subject
            .receive(on: DispatchQueue.global(qos: .default))
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
    
    func send_raw(_ req: String) {
        socket.send(.string(req))
    }
    
    func send(_ req: NostrRequestType) {
        switch req {
        case .typical(let req):
            guard let req = make_nostr_req(req) else {
                print("failed to encode nostr req: \(req)")
                return
            }
            send_raw(req)
            
        case .custom(let req):
            send_raw(req)
        }
    }
    
    private func receive(event: WebSocketEvent) {
        switch event {
        case .connected:
            DispatchQueue.main.async {
                self.backoff = 1.0
                self.isConnected = true
                self.isConnecting = false
            }
        case .message(let message):
            self.receive(message: message)
        case .disconnected(let closeCode, let reason):
            if closeCode != .normalClosure {
                print("⚠️ Warning: RelayConnection (\(self.url)) closed with code \(closeCode), reason: \(String(describing: reason))")
            }
            DispatchQueue.main.async {
                self.isConnected = false
                self.isConnecting = false
                self.reconnect()
            }
        case .error(let error):
            print("⚠️ Warning: RelayConnection (\(self.url)) error: \(error)")
            let nserr = error as NSError
            if nserr.domain == NSPOSIXErrorDomain && nserr.code == 57 {
                // ignore socket not connected?
                return
            }
            DispatchQueue.main.async {
                self.isConnected = false
                self.isConnecting = false
                self.reconnect_with_backoff()
            }
        }
        DispatchQueue.main.async {
            self.handleEvent(.ws_event(event))
        }
        
        if let description = event.description {
            log?.add(description)
        }
    }
    
    func reconnect_with_backoff() {
        self.backoff *= 1.5
        self.reconnect_in(after: self.backoff)
    }
    
    func reconnect() {
        guard !isConnecting else {
            return  // we're already trying to connect
        }
        disconnect()
        connect()
        log?.add("Reconnecting...")
    }
    
    func reconnect_in(after: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + after) {
            self.reconnect()
        }
    }
    
    private func receive(message: URLSessionWebSocketTask.Message) {
        switch message {
        case .string(let messageString):
            if let ev = decode_nostr_event(txt: messageString) {
                DispatchQueue.main.async {
                    self.handleEvent(.nostr_event(ev))
                }
                return
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
