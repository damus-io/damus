//
//  NostrConnection.swift
//  damus
//
//  Created by William Casarin on 2022-04-02.
//

import Combine
import Foundation

enum NostrConnectionEvent {
    /// Other non-message websocket events
    case ws_connection_event(WSConnectionEvent)
    /// A nostr response
    case nostr_event(NostrResponse)
    
    /// Models non-messaging websocket events
    ///
    /// Implementation note: Messaging events should use `.nostr_event` in `NostrConnectionEvent`
    enum WSConnectionEvent {
        case connected
        case disconnected(URLSessionWebSocketTask.CloseCode, String?)
        case error(Error)
        
        static func from(full_ws_event: WebSocketEvent) -> Self? {
            switch full_ws_event {
            case .connected:
                return .connected
            case .message(_):
                return nil
            case .disconnected(let closeCode, let string):
                return .disconnected(closeCode, string)
            case .error(let error):
                return .error(error)
            }
        }
    }
    
    var subId: String? {
        switch self {
        case .ws_connection_event(_):
            return nil
        case .nostr_event(let event):
            return event.subid
        }
    }
}

final class RelayConnection: ObservableObject {
    @Published private(set) var isConnected = false
    @Published private(set) var isConnecting = false
    private var isDisabled = false
    
    private(set) var last_connection_attempt: TimeInterval = 0
    private(set) var last_pong: Date? = nil
    private(set) var backoff: TimeInterval = 1.0
    private var socket: WebSocketProtocol
    private var subscriptionToken: AnyCancellable?

    private var handleEvent: (NostrConnectionEvent) async -> ()
    private var processEvent: (WebSocketEvent) -> ()
    private let relay_url: RelayURL
    var log: RelayLog?

    /// Creates a new RelayConnection
    /// - Parameters:
    ///   - url: The relay URL to connect to
    ///   - webSocket: Optional WebSocket implementation for dependency injection (defaults to real WebSocket)
    ///   - handleEvent: Callback for Nostr events
    ///   - processUnverifiedWSEvent: Callback for raw WebSocket events
    init(url: RelayURL,
         webSocket: WebSocketProtocol? = nil,
         handleEvent: @escaping (NostrConnectionEvent) async -> (),
         processUnverifiedWSEvent: @escaping (WebSocketEvent) -> ())
    {
        self.relay_url = url
        self.socket = webSocket ?? WebSocket(url.url)
        self.handleEvent = handleEvent
        self.processEvent = processUnverifiedWSEvent
    }
    
    func ping() {
        socket.ping { [weak self] err in
            guard let self else {
                return
            }
            
            if err == nil {
                self.last_pong = .now
                Log.info("Got pong from '%s'", for: .networking, self.relay_url.absoluteString)
                self.log?.add("Successful ping")
            } else {
                Log.info("Ping failed, reconnecting to '%s'", for: .networking, self.relay_url.absoluteString)
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
                    Task { await self?.receive(event: .error(error)) }
                case .finished:
                    Task { await self?.receive(event: .disconnected(.normalClosure, nil)) }
                }
            } receiveValue: { [weak self] event in
                Task { await self?.receive(event: event) }
            }
            
        socket.connect()
    }

    func disconnect() {
        socket.disconnect(closeCode: .normalClosure, reason: nil)
        subscriptionToken = nil

        isConnected = false
        isConnecting = false
    }
    
    func disablePermanently() {
        isDisabled = true
    }
    
    func send_raw(_ req: String) {
        socket.send(.string(req))
    }
    
    func send(_ req: NostrRequestType, callback: ((String) -> Void)? = nil) {
        switch req {
        case .typical(let req):
            guard let req = make_nostr_req(req) else {
                print("failed to encode nostr req: \(req)")
                return
            }
            send_raw(req)
            callback?(req)
            
        case .custom(let req):
            send_raw(req)
            callback?(req)
        }
    }
    
    private func receive(event: WebSocketEvent) async {
        assert(!Thread.isMainThread, "This code must not be executed on the main thread")
        processEvent(event)
        switch event {
        case .connected:
            DispatchQueue.main.async {
                self.backoff = 1.0
                self.isConnected = true
                self.isConnecting = false
            }
        case .message(let message):
            await self.receive(message: message)
        case .disconnected(let closeCode, let reason):
            if closeCode != .normalClosure {
                Log.error("⚠️ Warning: RelayConnection (%d) closed with code: %s", for: .networking, String(describing: closeCode), String(describing: reason))
            }
            DispatchQueue.main.async {
                self.isConnected = false
                self.isConnecting = false
                self.reconnect()
            }
        case .error(let error):
            Log.error("⚠️ Warning: RelayConnection (%s) error: %s", for: .networking, self.relay_url.absoluteString, error.localizedDescription)
            let nserr = error as NSError
            if nserr.domain == NSPOSIXErrorDomain && nserr.code == 57 {
                // ignore socket not connected?
                return
            }
            if nserr.domain == NSURLErrorDomain && nserr.code == -999 {
                // these aren't real error, it just means task was cancelled
                return
            }
            DispatchQueue.main.async {
                self.isConnected = false
                self.isConnecting = false
                self.reconnect_with_backoff()
            }
        }
        guard let ws_connection_event = NostrConnectionEvent.WSConnectionEvent.from(full_ws_event: event) else { return }
        await self.handleEvent(.ws_connection_event(ws_connection_event))
        
        if let description = event.description {
            log?.add(description)
        }
    }
    
    func reconnect_with_backoff() {
        self.backoff *= 2.0
        self.reconnect_in(after: self.backoff)
    }
    
    func reconnect() {
        guard !isConnecting && !isDisabled else {
            self.log?.add("Cancelling reconnect, already connecting")
            return  // we're already trying to connect or we're disabled
        }

        guard !self.isConnected else {
            self.log?.add("Cancelling reconnect, already connected")
            return
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
    
    private func receive(message: URLSessionWebSocketTask.Message) async {
        switch message {
        case .string(let messageString):
            // NOTE: Once we switch to the local relay model,
            // we will not need to verify nostr events at this point.
            if let ev = decode_and_verify_nostr_response(txt: messageString) {
                await self.handleEvent(.nostr_event(ev))
                return
            }
            print("failed to decode event \(messageString)")
        case .data(let messageData):
            if let messageString = String(data: messageData, encoding: .utf8) {
                await receive(message: .string(messageString))
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
    case .auth(let ev):
        return make_nostr_auth_event(ev: ev)
    }
}

func make_nostr_auth_event(ev: NostrEvent) -> String? {
    guard let event = encode_json(ev) else {
        return nil
    }
    let encoded = "[\"AUTH\",\(event)]"
    print(encoded)
    return encoded
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
