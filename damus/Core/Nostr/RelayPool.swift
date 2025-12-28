//
//  RelayPool.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation
import Network

struct RelayHandler {
    let sub_id: String
    /// The filters that this handler will handle. Set this to `nil` if you want your handler to receive all events coming from the relays.
    let filters: [NostrFilter]?
    let to: [RelayURL]?
    var handler: AsyncStream<(RelayURL, NostrConnectionEvent)>.Continuation
}

struct QueuedRequest {
    let req: NostrRequestType
    let relay: RelayURL
    let skip_ephemeral: Bool
}

struct SeenEvent: Hashable {
    let relay_id: RelayURL
    let evid: NoteId
}

/// Establishes and manages connections and subscriptions to a list of relays.
actor RelayPool {
    @MainActor
    private(set) var relays: [Relay] = []
    var open: Bool = false
    var handlers: [RelayHandler] = []
    var request_queue: [QueuedRequest] = []
    var seen: [NoteId: Set<RelayURL>] = [:]
    var counts: [RelayURL: UInt64] = [:]
    var ndb: Ndb?
    /// The keypair used to authenticate with relays
    var keypair: Keypair?
    var message_received_function: (((String, RelayDescriptor)) -> Void)?
    var message_sent_function: (((String, Relay)) -> Void)?
    var delegate: Delegate?
    private(set) var signal: SignalModel = SignalModel()

    let network_monitor = NWPathMonitor()
    private let network_monitor_queue = DispatchQueue(label: "io.damus.network_monitor")
    private var last_network_status: NWPath.Status = .unsatisfied
    
    /// The limit of maximum concurrent subscriptions. Any subscriptions beyond this limit will be paused until subscriptions clear
    /// This is to avoid error states and undefined behaviour related to hitting subscription limits on the relays, by letting those wait instead — with the principle that although slower is not ideal, it is better than completely broken.
    static let MAX_CONCURRENT_SUBSCRIPTION_LIMIT = 14   // This number is only an educated guess based on some local experiments.

    func close() async {
        await disconnect()
        await clearRelays()
        open = false
        handlers = []
        request_queue = []
        await clearSeen()
        counts = [:]
        keypair = nil
    }
    
    @MainActor
    private func clearRelays() {
        relays = []
    }
    
    private func clearSeen() {
        seen.removeAll()
    }

    init(ndb: Ndb?, keypair: Keypair? = nil) {
        self.ndb = ndb
        self.keypair = keypair

        network_monitor.pathUpdateHandler = { [weak self] path in
            Task { await self?.pathUpdateHandler(path: path) }
        }
        network_monitor.start(queue: network_monitor_queue)
    }
    
    private func pathUpdateHandler(path: NWPath) async {
        if (path.status == .satisfied || path.status == .requiresConnection) && self.last_network_status != path.status {
            await self.connect_to_disconnected()
        }
        
        if path.status != self.last_network_status {
            for relay in await self.relays {
                relay.connection.log?.add("Network state: \(path.status)")
            }
        }
        
        self.last_network_status = path.status
    }
    
    @MainActor
    var our_descriptors: [RelayDescriptor] {
        return all_descriptors.filter { d in !d.ephemeral }
    }
    
    @MainActor
    var all_descriptors: [RelayDescriptor] {
        relays.map { r in r.descriptor }
    }
    
    @MainActor
    var num_connected: Int {
        return relays.reduce(0) { n, r in n + (r.connection.isConnected ? 1 : 0) }
    }

    func remove_handler(sub_id: String) {
        self.handlers = handlers.filter {
            if $0.sub_id != sub_id {
                return true
            }
            else {
                $0.handler.finish()
                return false
            }
        }
        Log.debug("Removing %s handler, current: %d", for: .networking, sub_id, handlers.count)
    }
    
    func ping() async {
        Log.info("Pinging %d relays", for: .networking, await relays.count)
        for relay in await relays {
            relay.connection.ping()
        }
    }

    func register_handler(sub_id: String, filters: [NostrFilter]?, to relays: [RelayURL]? = nil, handler: AsyncStream<(RelayURL, NostrConnectionEvent)>.Continuation) async {
        while handlers.count > Self.MAX_CONCURRENT_SUBSCRIPTION_LIMIT {
            Log.debug("%s: Too many subscriptions, waiting for subscription pool to clear", for: .networking, sub_id)
            try? await Task.sleep(for: .seconds(1))
        }
        Log.debug("%s: Subscription pool cleared", for: .networking, sub_id)
        handlers = handlers.filter({ handler in
            if handler.sub_id == sub_id {
                Log.error("Duplicate handler detected for the same subscription ID. Overriding.", for: .networking)
                handler.handler.finish()
                return false
            }
            else {
                return true
            }
        })
        self.handlers.append(RelayHandler(sub_id: sub_id, filters: filters, to: relays, handler: handler))
        Log.debug("Registering %s handler, current: %d", for: .networking, sub_id, self.handlers.count)
    }

    @MainActor
    func remove_relay(_ relay_id: RelayURL) async {
        var i: Int = 0

        await self.disconnect(to: [relay_id])

        for relay in relays {
            if relay.id == relay_id {
                relay.connection.disablePermanently()
                relays.remove(at: i)
                break
            }

            i += 1
        }
    }

    /// Removes ephemeral relays from the pool and disconnects them.
    /// Only removes relays that are marked as ephemeral; regular relays are left untouched.
    ///
    /// - Parameter relayURLs: The relay URLs to potentially remove (only ephemeral ones will be removed)
    func removeEphemeralRelays(_ relayURLs: [RelayURL]) async {
        for url in relayURLs {
            if let relay = await get_relay(url), relay.descriptor.ephemeral {
                #if DEBUG
                print("[RelayPool] Removing ephemeral relay: \(url.absoluteString)")
                #endif
                await remove_relay(url)
            }
        }
    }

    func add_relay(_ desc: RelayDescriptor) async throws(RelayError) {
        let relay_id = desc.url
        if await get_relay(relay_id) != nil {
            throw RelayError.RelayAlreadyExists
        }
        let conn = RelayConnection(url: desc.url, handleEvent: { event in
            await self.handle_event(relay_id: relay_id, event: event)
        }, processUnverifiedWSEvent: { wsev in
            guard case .message(let msg) = wsev,
                  case .string(let str) = msg
            else { return }

            let _ = self.ndb?.processEvent(str, originRelayURL: relay_id)
            self.message_received_function?((str, desc))
        })
        let relay = Relay(descriptor: desc, connection: conn)
        await self.appendRelayToList(relay: relay)
    }
    
    @MainActor
    private func appendRelayToList(relay: Relay) {
        self.relays.append(relay)
    }

    /// Ensures the given relay URLs are connected, adding them as ephemeral relays if not already in the pool.
    /// Returns the list of relay URLs that are actually connected (ready for subscriptions).
    ///
    /// Ephemeral relays should be cleaned up by the caller after the lookup completes using `removeEphemeralRelays`.
    ///
    /// - Parameters:
    ///   - relayURLs: The relay URLs to ensure are connected
    ///   - timeout: Maximum time to wait for pending connections (default 2s). Returns early when first relay connects.
    /// - Returns: Connected relay URLs ready for subscriptions
    func ensureConnected(to relayURLs: [RelayURL], timeout: Duration = .seconds(2)) async -> [RelayURL] {
        var toConnect: [RelayURL] = []
        var alreadyConnected: [RelayURL] = []

        for url in relayURLs {
            if let existing = await get_relay(url) {
                if existing.connection.isConnected {
                    alreadyConnected.append(url)
                    #if DEBUG
                    print("[RelayPool] Relay \(url.absoluteString) already connected")
                    #endif
                } else {
                    toConnect.append(url)
                }
                continue
            }

            let descriptor = RelayDescriptor(url: url, info: .readWrite, variant: .ephemeral)
            do {
                try await add_relay(descriptor)
                toConnect.append(url)
                #if DEBUG
                print("[RelayPool] Added ephemeral relay: \(url.absoluteString)")
                #endif
            } catch {
                #if DEBUG
                print("[RelayPool] Failed to add relay \(url.absoluteString): \(error)")
                #endif
            }
        }

        guard !toConnect.isEmpty else { return alreadyConnected }

        await connect(to: toConnect)

        let deadline = ContinuousClock.now + timeout
        let checkInterval: Duration = .milliseconds(100)

        waitLoop: while ContinuousClock.now < deadline {
            do {
                try await Task.sleep(for: checkInterval)
            } catch {
                break
            }

            for url in toConnect {
                if let relay = await get_relay(url), relay.connection.isConnected {
                    break waitLoop
                }
            }
        }

        var connected = alreadyConnected
        for url in toConnect {
            if let relay = await get_relay(url), relay.connection.isConnected {
                connected.append(url)
                #if DEBUG
                print("[RelayPool] Relay \(url.absoluteString) connected: true")
                #endif
            } else {
                #if DEBUG
                print("[RelayPool] Relay \(url.absoluteString) connected: false (excluded)")
                #endif
            }
        }

        return connected
    }

    func setLog(_ log: RelayLog, for relay_id: RelayURL) async {
        // add the current network state to the log
        log.add("Network state: \(network_monitor.currentPath.status)")

        await get_relay(relay_id)?.connection.log = log
    }
    
    /// This is used to retry dead connections
    func connect_to_disconnected() async {
        for relay in await relays {
            let c = relay.connection
            
            let is_connecting = c.isConnecting

            if is_connecting && (Date.now.timeIntervalSince1970 - c.last_connection_attempt) > 5 {
                print("stale connection detected (\(relay.descriptor.url.absoluteString)). retrying...")
                relay.connection.reconnect()
            } else if relay.is_broken || is_connecting || c.isConnected {
                continue
            } else {
                relay.connection.reconnect()
            }
            
        }
    }

    func reconnect(to targetRelays: [RelayURL]? = nil) async {
        let relays = await getRelays(targetRelays: targetRelays)
        for relay in relays {
            // don't try to reconnect to broken relays
            relay.connection.reconnect()
        }
    }

    func connect(to targetRelays: [RelayURL]? = nil) async {
        let relays = await getRelays(targetRelays: targetRelays)
        for relay in relays {
            relay.connection.connect()
        }
        // Mark as open last, to prevent other classes from pulling data before the relays are actually connected
        open = true
    }

    func disconnect(to targetRelays: [RelayURL]? = nil) async {
        // Mark as closed first, to prevent other classes from pulling data while the relays are being disconnected
        open = false
        let relays = await getRelays(targetRelays: targetRelays)
        for relay in relays {
            relay.connection.disconnect()
        }
    }
    
    @MainActor
    func getRelays(targetRelays: [RelayURL]? = nil) -> [Relay] {
        targetRelays.map{ get_relays($0) } ?? self.relays
    }
    
    /// Deletes queued up requests that should not persist between app sessions (i.e. when the app goes to background then back to foreground)
    func cleanQueuedRequestForSessionEnd() {
        request_queue = request_queue.filter { request in
            guard case .typical(let typicalRequest) = request.req else { return true }
            switch typicalRequest {
            case .subscribe(_):
                return true
            case .unsubscribe(_):
                return false    // Do not persist unsubscribe requests to prevent them to race against subscribe requests when we come back to the foreground.
            case .event(_):
                return true
            case .auth(_):
                return true
            }
        }
    }

    func unsubscribe(sub_id: String, to: [RelayURL]? = nil) async {
        if to == nil {
            self.remove_handler(sub_id: sub_id)
        }
        await self.send(.unsubscribe(sub_id), to: to)
    }

    func subscribe(sub_id: String, filters: [NostrFilter], handler: AsyncStream<(RelayURL, NostrConnectionEvent)>.Continuation, to: [RelayURL]? = nil) {
        Task {
            await register_handler(sub_id: sub_id, filters: filters, to: to, handler: handler)
            
            // When the caller specifies no relays, it is implied that the user wants to use the ones in the user relay list. Skip ephemeral relays in that case.
            // When the caller specifies specific relays, do not skip ephemeral relays to respect the exact list given by the caller.
            let shouldSkipEphemeralRelays = to == nil ? true : false
            
            await send(.subscribe(.init(filters: filters, sub_id: sub_id)), to: to, skip_ephemeral: shouldSkipEphemeralRelays)
        }
    }
    
    /// Subscribes to data from the `RelayPool` based on a filter and a list of desired relays.
    /// 
    /// - Parameters:
    ///   - filters: The filters specifying the desired content.
    ///   - desiredRelays: The desired relays which to subsctibe to. If `nil`, it defaults to the `RelayPool`'s default list
    ///   - eoseTimeout: The maximum timeout which to give up waiting for the eoseSignal
    /// - Returns: Returns an async stream that callers can easily consume via a for-loop
    func subscribe(filters: [NostrFilter], to desiredRelays: [RelayURL]? = nil, eoseTimeout: Duration? = nil, id: UUID? = nil) async -> AsyncStream<StreamItem> {
        let eoseTimeout = eoseTimeout ?? .seconds(5)
        let desiredRelays = await getRelays(targetRelays: desiredRelays)
        let startTime = CFAbsoluteTimeGetCurrent()
        return AsyncStream<StreamItem> { continuation in
            let id = id ?? UUID()
            let sub_id = id.uuidString
            var seenEvents: Set<NoteId> = []
            var relaysWhoFinishedInitialResults: Set<RelayURL> = []
            var eoseSent = false
            let upstreamStream = AsyncStream<(RelayURL, NostrConnectionEvent)> { upstreamContinuation in
                self.subscribe(sub_id: sub_id, filters: filters, handler: upstreamContinuation, to: desiredRelays.map({ $0.descriptor.url }))
            }
            let upstreamStreamingTask = Task {
                for await (relayUrl, connectionEvent) in upstreamStream {
                    try Task.checkCancellation()
                    switch connectionEvent {
                    case .ws_connection_event(let ev):
                        // Websocket events such as connect/disconnect/error are already handled in `RelayConnection`. Do not perform any handling here.
                        // For the future, perhaps we should abstract away `.ws_connection_event` in `RelayPool`? Seems like something to be handled on the `RelayConnection` layer.
                        break
                    case .nostr_event(let nostrResponse):
                        guard nostrResponse.subid == sub_id else { return } // Do not stream items that do not belong in this subscription
                        switch nostrResponse {
                        case .event(_, let nostrEvent):
                            if seenEvents.contains(nostrEvent.id) { break } // Don't send two of the same events.
                            continuation.yield(with: .success(.event(nostrEvent)))
                            seenEvents.insert(nostrEvent.id)
                        case .notice(let note):
                            break   // We do not support handling these yet
                        case .eose(_):
                            relaysWhoFinishedInitialResults.insert(relayUrl)
                            let desiredAndConnectedRelays = desiredRelays.filter({ $0.connection.isConnected }).map({ $0.descriptor.url })
                            Log.debug("RelayPool subscription %s: EOSE from %s. EOSE count: %d/%d. Elapsed: %.2f seconds.", for: .networking, id.uuidString, relayUrl.absoluteString, relaysWhoFinishedInitialResults.count, Set(desiredAndConnectedRelays).count, CFAbsoluteTimeGetCurrent() - startTime)
                            if relaysWhoFinishedInitialResults == Set(desiredAndConnectedRelays) {
                                continuation.yield(with: .success(.eose))
                                eoseSent = true
                            }
                        case .ok(_): break    // No need to handle this, we are not sending an event to the relay
                        case .auth(_): break    // Handled in a separate function in RelayPool
                        }
                    }
                }
            }
            let timeoutTask = Task {
                try? await Task.sleep(for: eoseTimeout)
                if !eoseSent { continuation.yield(with: .success(.eose)) }
            }
            continuation.onTermination = { @Sendable termination in
                switch termination {
                case .finished:
                    Log.debug("RelayPool subscription %s finished. Closing.", for: .networking, sub_id)
                case .cancelled:
                    Log.debug("RelayPool subscription %s cancelled. Closing.", for: .networking, sub_id)
                @unknown default:
                    break
                }
                Task {
                    await self.unsubscribe(sub_id: sub_id, to: desiredRelays.map({ $0.descriptor.url }))
                    await self.remove_handler(sub_id: sub_id)
                }
                timeoutTask.cancel()
                upstreamStreamingTask.cancel()
            }
        }
    }
    
    enum StreamItem {
        /// A Nostr event
        case event(NostrEvent)
        /// The "end of stored events" signal
        case eose
    }

    func subscribe_to(sub_id: String, filters: [NostrFilter], to: [RelayURL]?, handler: AsyncStream<(RelayURL, NostrConnectionEvent)>.Continuation) {
        Task {
            await register_handler(sub_id: sub_id, filters: filters, to: to, handler: handler)
            
            await send(.subscribe(.init(filters: filters, sub_id: sub_id)), to: to)
        }
    }

    func count_queued(relay: RelayURL) -> Int {
        var c = 0
        for request in request_queue {
            if request.relay == relay {
                c += 1
            }
        }
        
        return c
    }
    
    func queue_req(r: NostrRequestType, relay: RelayURL, skip_ephemeral: Bool) {
        let count = count_queued(relay: relay)
        guard count <= 10 else {
            print("can't queue, too many queued events for \(relay)")
            return
        }
        
        print("queueing request for \(relay)")
        request_queue.append(QueuedRequest(req: r, relay: relay, skip_ephemeral: skip_ephemeral))
    }
    
    func send_raw_to_local_ndb(_ req: NostrRequestType) {
        // send to local relay (nostrdb)
        switch req {
            case .typical(let r):
                if case .event = r, let rstr = make_nostr_req(r) {
                    let _ = ndb?.process_client_event(rstr)
                }
            case .custom(let string):
                let _ = ndb?.process_client_event(string)
        }
    }

    func send_raw(_ req: NostrRequestType, to: [RelayURL]? = nil, skip_ephemeral: Bool = true) async {
        let relays = await getRelays(targetRelays: to)

        self.send_raw_to_local_ndb(req)     // Always send Nostr events and data to NostrDB for a local copy

        for relay in relays {
            if req.is_read && !(relay.descriptor.info.canRead) {
                continue    // Do not send read requests to relays that are not READ relays
            }
            
            if req.is_write && !(relay.descriptor.info.canWrite) {
                continue    // Do not send write requests to relays that are not WRITE relays
            }
            
            if relay.descriptor.ephemeral && skip_ephemeral {
                continue    // Do not send requests to ephemeral relays if we want to skip them
            }
            
            guard relay.connection.isConnected else {
                Task { await queue_req(r: req, relay: relay.id, skip_ephemeral: skip_ephemeral) }
                continue
            }
            
            relay.connection.send(req, callback: { str in
                self.message_sent_function?((str, relay))
            })
        }
    }

    func send(_ req: NostrRequest, to: [RelayURL]? = nil, skip_ephemeral: Bool = true) async {
        await send_raw(.typical(req), to: to, skip_ephemeral: skip_ephemeral)
    }

    @MainActor
    func get_relays(_ ids: [RelayURL]) -> [Relay] {
        // don't include ephemeral relays in the default list to query
        relays.filter { ids.contains($0.id) }
    }

    @MainActor
    func get_relay(_ id: RelayURL) -> Relay? {
        relays.first(where: { $0.id == id })
    }

    func run_queue(_ relay_id: RelayURL) {
        self.request_queue = request_queue.reduce(into: Array<QueuedRequest>()) { (q, req) in
            guard req.relay == relay_id else {
                q.append(req)
                return
            }
            
            print("running queueing request: \(req.req) for \(relay_id)")
            Task { await self.send_raw(req.req, to: [relay_id], skip_ephemeral: false) }
        }
    }

    func record_seen(relay_id: RelayURL, event: NostrConnectionEvent) {
        if case .nostr_event(let ev) = event {
            if case .event(_, let nev) = ev {
                if seen[nev.id]?.contains(relay_id) == true {
                    return
                }
                seen[nev.id, default: Set()].insert(relay_id)
                counts[relay_id, default: 0] += 1
                notify(.update_stats(note_id: nev.id))
            }
        }
    }
    
    func resubscribeAll(relayId: RelayURL) async {
        for handler in self.handlers {
            guard let filters = handler.filters else { continue }
            // When the caller specifies no relays, it is implied that the user wants to use the ones in the user relay list. Skip ephemeral relays in that case.
            // When the caller specifies specific relays, do not skip ephemeral relays to respect the exact list given by the caller.
            let shouldSkipEphemeralRelays = handler.to == nil ? true : false
            
            if let handlerTargetRelays = handler.to,
               !handlerTargetRelays.contains(where: { $0 == relayId }) {
                // Not part of the target relays, skip
                continue
            }
            
            Log.debug("%s: Sending resubscribe request to %s", for: .networking, handler.sub_id, relayId.absoluteString)
            await send(.subscribe(.init(filters: filters, sub_id: handler.sub_id)), to: [relayId], skip_ephemeral: shouldSkipEphemeralRelays)
        }
    }

    func handle_event(relay_id: RelayURL, event: NostrConnectionEvent) async {
        record_seen(relay_id: relay_id, event: event)

        // When we reconnect, do two things
        // - Send messages that were stored in the queue
        // - Re-subscribe to filters we had subscribed before
        if case .ws_connection_event(let ws) = event {
            if case .connected = ws {
                run_queue(relay_id)
                await self.resubscribeAll(relayId: relay_id)
            }
        }

        // Handle auth
        if case let .nostr_event(nostrResponse) = event,
           case let .auth(challenge_string) = nostrResponse {
            if let relay = await get_relay(relay_id) {
                print("received auth request from \(relay.descriptor.url.id)")
                relay.authentication_state = .pending
                if let keypair {
                    if let fullKeypair = keypair.to_full() {
                        if let authRequest = make_auth_request(keypair: fullKeypair, challenge_string: challenge_string, relay: relay) {
                            await send(.auth(authRequest), to: [relay_id], skip_ephemeral: false)
                            relay.authentication_state = .verified
                        } else {
                            print("failed to make auth request")
                        }
                    } else {
                        print("keypair provided did not contain private key, can not sign auth request")
                        relay.authentication_state = .error(.no_private_key)
                    }
                } else {
                    print("no keypair to reply to auth request")
                    relay.authentication_state = .error(.no_key)
                }
            } else {
                print("no relay found for \(relay_id)")
            }
        }

        for handler in handlers {
            // We send data to the handlers if:
            // - the subscription ID matches, or
            // - the handler filters is `nil`, which is used in some cases as a blanket "give me all notes" (e.g. during signup)
            guard handler.sub_id == event.subId || handler.filters == nil else { continue }
            logStreamPipelineStats("RelayPool_\(relay_id.absoluteString)", "RelayPool_Handler_\(handler.sub_id)")
            handler.handler.yield((relay_id, event))
        }
    }
}

func add_rw_relay(_ pool: RelayPool, _ url: RelayURL) async {
    try? await pool.add_relay(RelayPool.RelayDescriptor(url: url, info: .readWrite))
}


extension RelayPool {
    protocol Delegate {
        func latestRelayListChanged(_ newEvent: NdbNote)
    }
}


