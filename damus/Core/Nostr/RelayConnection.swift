//
//  NostrConnection.swift
//  damus
//
//  Created by William Casarin on 2022-04-02.
//

import Combine
import Foundation
import Negentropy

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
    
    /// The queue of WebSocket events to be processed
    /// We need this queue to ensure events are processed and sent to RelayPool in the exact order in which they arrive.
    /// See `processEventsTask()` for more information
    var wsEventQueue: QueueableNotify<WebSocketEvent>
    /// The task which will process WebSocket events in the order in which we receive them from the wire
    var wsEventProcessTask: Task<Void, any Error>?
    
    @RelayPoolActor // Isolate this to a specific actor to avoid thread-satefy issues.
    var negentropyStreams: [String: AsyncStream<NegentropyResponse>.Continuation] = [:]

    init(url: RelayURL,
         handleEvent: @escaping (NostrConnectionEvent) async -> (),
         processUnverifiedWSEvent: @escaping (WebSocketEvent) -> ())
    {
        self.relay_url = url
        self.handleEvent = handleEvent
        self.processEvent = processUnverifiedWSEvent
        self.wsEventQueue = .init(maxQueueItems: 1000)
        self.wsEventProcessTask = nil
        self.wsEventProcessTask = Task {
            try await self.processEventsTask()
        }
    }
    
    deinit {
        self.wsEventProcessTask?.cancel()
    }
    
    /// The task that will stream the queue of WebSocket events to be processed
    /// We need this in order to ensure events are processed and sent to RelayPool in the exact order in which they arrive.
    ///
    /// We need this (or some equivalent syncing mechanism) because without it, two WebSocket events can be processed concurrently,
    /// and sometimes sent in the wrong order due to difference in processing timing.
    ///
    /// For example, streaming a filter that yields 1 event can cause the EOSE signal to arrive in RelayPool before the event, simply because the event
    /// takes longer to process compared to the EOSE signal.
    ///
    /// To prevent this, we send raw WebSocket events to this queue BEFORE any processing (to ensure equal timing),
    /// and then process the queue in the order in which they appear
    func processEventsTask() async throws {
        for await item in await self.wsEventQueue.stream {
            try Task.checkCancellation()
            await self.receive(event: item)
        }
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
                // @Published writes must happen on the main thread to avoid
                // SwiftUI crashes. The ping callback fires on an arbitrary thread.
                DispatchQueue.main.async {
                    self.isConnected = false
                    self.isConnecting = false
                    self.reconnect_with_backoff()
                }
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
                    Task { await self?.wsEventQueue.add(item: .error(error)) }
                case .finished:
                    Task { await self?.wsEventQueue.add(item: .disconnected(.normalClosure, nil)) }
                }
            } receiveValue: { [weak self] event in
                Task { await self?.wsEventQueue.add(item: event) }
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
            // NOTE: Once we switch to the local relay model,
            // we will not need to verify nostr events at this point.
            if let ev = decode_and_verify_nostr_response(txt: messageString) {
                await self.handleEvent(.nostr_event(ev))
                if let negentropyResponse = ev.negentropyResponse {
                    await self.negentropyStreams[negentropyResponse.subscriptionId]?.yield(negentropyResponse)
                }
                return
            }
            print("\(self.relay_url): failed to decode event \(messageString)")
        case .data(let messageData):
            if let messageString = String(data: messageData, encoding: .utf8) {
                await receive(message: .string(messageString))
            }
        @unknown default:
            print("An unexpected URLSessionWebSocketTask.Message was received.")
        }
    }
    
    // MARK: - Negentropy logic
    
    /// Retrieves the IDs of events missing locally compared to the relay using negentropy protocol.
    ///
    /// - Parameters:
    ///   - filter: The Nostr filter to scope the sync
    ///   - negentropyVector: The local storage vector for comparison
    ///   - timeout: Optional timeout for the operation
    /// - Returns: Array of IDs that the relay has but we don't
    /// - Throws: NegentropySyncError on failure
    @RelayPoolActor
    func getMissingIds(filter: NostrFilter, negentropyVector: NegentropyStorageVector, timeout: Duration?) async throws -> [Id] {
        if let relayMetadata = try? await fetch_relay_metadata(relay_id: self.relay_url),
           let supportsNegentropy = relayMetadata.supports_negentropy {
            if !supportsNegentropy {
                // Throw an error if the relay specifically advertises that there is no support for negentropy
                throw NegentropySyncError.notSupported
            }
        }
        let timeout = timeout ?? .seconds(3)
        let frameSizeLimit = 60_000 // Copied from rust-nostr project: Default frame limit is 128k. Halve that (hex encoding) and subtract a bit (JSON msg overhead)
        try? negentropyVector.seal()    // Error handling note: We do not care if it throws an `alreadySealed` error. As long as it is sealed in the end it is fine
        let negentropyClient = try Negentropy(storage: negentropyVector, frameSizeLimit: frameSizeLimit)
        let initialMessage = try negentropyClient.initiate()
        let subscriptionId = UUID().uuidString
        var allNeedIds: [Id] = []
        for await response in negentropyStream(subscriptionId: subscriptionId, filter: filter, initialMessage: initialMessage, timeoutDuration: timeout) {
            switch response {
            case .error(subscriptionId: _, reasonCodeString: let reasonCodeString):
                throw NegentropySyncError.genericError(reasonCodeString)
            case .message(subscriptionId: _, data: let data):
                var haveIds: [Id] = []
                var needIds: [Id] = []
                let nextMessage = try negentropyClient.reconcile(data, haveIds: &haveIds, needIds: &needIds)
                allNeedIds.append(contentsOf: needIds)
                if let nextMessage {
                    self.send(.typical(.negentropyMessage(subscriptionId: subscriptionId, message: nextMessage)))
                }
                else {
                    // Reconciliation is complete
                    return allNeedIds
                }
            case .invalidResponse(subscriptionId: _):
                throw NegentropySyncError.relayError
            }
        }
        // If the stream completes without a response, throw a timeout/relay error
        throw NegentropySyncError.relayError
    }
    
    enum NegentropySyncError: Error {
        /// Fallback generic error
        case genericError(String)
        /// Negentropy is not supported by the relay
        case notSupported
        /// Something went wrong with the relay communication during negentropy sync
        case relayError
    }
    
    @RelayPoolActor
    private func negentropyStream(subscriptionId: String, filter: NostrFilter, initialMessage: [UInt8], timeoutDuration: Duration? = nil) -> AsyncStream<NegentropyResponse> {
        return AsyncStream<NegentropyResponse> { continuation in
            self.negentropyStreams[subscriptionId] = continuation
            let nostrRequest: NostrRequest = .negentropyOpen(subscriptionId: subscriptionId, filter: filter, initialMessage: initialMessage)
            self.send(.typical(nostrRequest))
            let timeoutTask = Task {
                if let timeoutDuration {
                    try Task.checkCancellation()
                    try await Task.sleep(for: timeoutDuration)
                    try Task.checkCancellation()
                    continuation.finish()
                }
            }
            continuation.onTermination = { @Sendable _ in
                Task {
                    await self.removeNegentropyStream(id: subscriptionId)
                    self.send(.typical(.negentropyClose(subscriptionId: subscriptionId)))
                }
                timeoutTask.cancel()
            }
        }
    }
    
    @RelayPoolActor
    private func removeNegentropyStream(id: String) {
        self.negentropyStreams[id] = nil
    }
}
