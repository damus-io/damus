//
//  NostrConnection.swift
//  damus
//
//  Created by William Casarin on 2022-04-02.
//

import Combine
import Foundation
import Negentropy

private actor NegentropyContinuationStore {
    private var continuations: [String: AsyncStream<NegentropyResponse>.Continuation] = [:]
    
    func set(_ continuation: AsyncStream<NegentropyResponse>.Continuation, for id: String) {
        continuations[id] = continuation
    }
    
    func clear(_ id: String) {
        continuations[id] = nil
    }
    
    func yield(_ response: NegentropyResponse) {
        continuations[response.subscriptionId]?.yield(response)
    }
}

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
    private lazy var socket = WebSocket(relay_url.url)
    private var subscriptionToken: AnyCancellable?

    private var handleEvent: (NostrConnectionEvent) async -> ()
    private var processEvent: (WebSocketEvent) -> ()
    private let relay_url: RelayURL
    var log: RelayLog?
    
    private let negentropyStreams = NegentropyContinuationStore()

    init(url: RelayURL,
         handleEvent: @escaping (NostrConnectionEvent) async -> (),
         processUnverifiedWSEvent: @escaping (WebSocketEvent) -> ())
    {
        self.relay_url = url
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
        socket.disconnect()
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
            // Parse negentropy frames before nostrdb, since nostrdb does not know about NIP-77.
            if let negentropyResponse = decode_negentropy_response(txt: messageString) {
                await negentropyStreams.yield(negentropyResponse)
                return
            }
            
            // NOTE: Once we switch to the local relay model,
            // we will not need to verify nostr events at this point.
            if let ev = decode_and_verify_nostr_response(txt: messageString) {
                await self.handleEvent(.nostr_event(ev))
                if let negentropyResponse = ev.negentropyResponse {
                    await negentropyStreams.yield(negentropyResponse)
                }
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
    
    // MARK: - Negentropy logic
    
    func getMissingIds(filters: [NostrFilter], negentropyVector: NegentropyStorageVector, timeout: Duration?) async throws -> [Id] {
        let timeout = timeout ?? .seconds(5)
        // Cap frames to keep hex-encoded messages within relay limits.
        let frameSizeLimit = 60_000 // Copied from rust-nostr project: Default frame limit is 128k. Halve that (hex encoding) and subtract a bit (JSON msg overhead)
        try negentropyVector.seal()
        var negentropyClient = try Negentropy(storage: negentropyVector, frameSizeLimit: frameSizeLimit)
        let subscriptionId = UUID().uuidString
        let initialMessage = try negentropyClient.initiate()
        Log.info("Negentropy open %s -> sending %d bytes", for: .networking, subscriptionId, initialMessage.count)
        var needIds: [Id] = []
        var haveIds: [Id] = []
        
        for await response in negentropyStream(subscriptionId: subscriptionId, filters: filters, initialMessage: initialMessage, timeoutDuration: timeout) {
            switch response {
            case .error(subscriptionId: _, reasonCodeString: let reasonCodeString):
                Log.error("Negentropy error from relay: %s", for: .networking, reasonCodeString)
                throw NegentropySyncError.genericError(reasonCodeString)
            case .message(subscriptionId: _, data: let data):
                var nextHave: [Id] = []
                var nextNeed: [Id] = []
                let nextMessage = try negentropyClient.reconcile(data, haveIds: &nextHave, needIds: &nextNeed)
                needIds.append(contentsOf: nextNeed)
                haveIds.append(contentsOf: nextHave)
                
                guard let nextMessage else {
                    // Finished reconciliation.
                    Log.info("Negentropy complete %s -> need %d ids", for: .networking, subscriptionId, needIds.count)
                    return needIds
                }
                
                // Keep going until reconcile returns nil.
                Log.info("Negentropy msg %s -> sending %d bytes", for: .networking, subscriptionId, nextMessage.count)
                self.send(.typical(.negentropyMessage(subscriptionId: subscriptionId, message: nextMessage)))
            case .invalidResponse(subscriptionId: _):
                throw NegentropySyncError.relayError
            }
        }
        // If the stream completes without a response, throw a timeout/relay error
        throw NegentropySyncError.relayError
    }
    
    enum NegentropySyncError: Error {
        case genericError(String)
        case relayError
    }
    
    private func negentropyStream(subscriptionId: String, filters: [NostrFilter], initialMessage: [UInt8], timeoutDuration: Duration? = nil) -> AsyncStream<NegentropyResponse> {
        return AsyncStream<NegentropyResponse> { continuation in
            Task { await self.negentropyStreams.set(continuation, for: subscriptionId) }
            let nostrRequest: NostrRequest = .negentropyOpen(subscriptionId: subscriptionId, filters: filters, initialMessage: initialMessage)
            self.send(.typical(nostrRequest))
            // Respect caller timeout so the protocol can't hang forever.
            let timeoutTask = Task {
                if let timeoutDuration {
                    try Task.checkCancellation()
                    try await Task.sleep(for: timeoutDuration)
                    try Task.checkCancellation()
                    continuation.finish()
                }
            }
            continuation.onTermination = { @Sendable _ in
                Task { await self.negentropyStreams.clear(subscriptionId) }
                self.send(.typical(.negentropyClose(subscriptionId: subscriptionId)))
                timeoutTask.cancel()
            }
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
    case .negentropyOpen(subscriptionId: let subscriptionId, filters: let filters, initialMessage: let initialMessage):
        return make_nostr_negentropy_open_req(subscriptionId: subscriptionId, filters: filters, initialMessage: initialMessage)
    case .negentropyMessage(subscriptionId: let subscriptionId, message: let message):
        return make_nostr_negentropy_message_req(subscriptionId: subscriptionId, message: message)
    case .negentropyClose(subscriptionId: let subscriptionId):
        return make_nostr_negentropy_close_req(subscriptionId: subscriptionId)
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

func make_nostr_negentropy_open_req(subscriptionId: String, filters: [NostrFilter], initialMessage: [UInt8]) -> String? {
    let encoder = JSONEncoder()
    guard let filter = filters.first else {
        return nil
    }
    let messageData = Data(initialMessage)
    let messageHex = hex_encode(messageData)
    var req = "[\"NEG-OPEN\",\"\(subscriptionId)\""
    guard let filter_json = try? encoder.encode(filter) else {
        return nil
    }
    let filter_json_str = String(decoding: filter_json, as: UTF8.self)
    req += ",\(filter_json_str),\"\(messageHex)\""
    req += "]"
    return req
}

func make_nostr_negentropy_message_req(subscriptionId: String, message: [UInt8]) -> String? {
    let messageData = Data(message)
    let messageHex = hex_encode(messageData)
    return "[\"NEG-MSG\",\"\(subscriptionId)\",\"\(messageHex)\"]"
}

func make_nostr_negentropy_close_req(subscriptionId: String) -> String? {
    return "[\"NEG-CLOSE\",\"\(subscriptionId)\"]"
}

private func decode_negentropy_response(txt: String) -> NegentropyResponse? {
    guard let data = txt.data(using: .utf8) else { return nil }
    guard let arr = try? JSONSerialization.jsonObject(with: data) as? [Any], arr.count >= 3 else {
        return nil
    }
    guard let type = arr[0] as? String,
          let subscriptionId = arr[1] as? String else { return nil }
    
    if type == "NEG-ERR" {
        guard let reason = arr[2] as? String else { return nil }
        return .error(subscriptionId: subscriptionId, reasonCodeString: reason)
    }
    
    if type == "NEG-MSG" {
        guard let hex = arr[2] as? String,
              let bytes = hex_decode(hex) else { return nil }
        return .message(subscriptionId: subscriptionId, data: bytes)
    }
    
    return nil
}
