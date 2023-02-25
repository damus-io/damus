//
//  RelayPool.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation

struct RelayHandler {
    let sub_id: String
    let callback: (String, NostrConnectionEvent) -> ()
}

struct QueuedRequest {
    let req: NostrRequest
    let relay: String
}

final class RelayPool {
    private enum Constants {
        /// Used for an exponential backoff algorithm when retrying stale connections
        /// Each retry attempt will be delayed by raising this base delay to an exponent
        /// equal to the number of previous retries.
        static let base_reconnect_delay: TimeInterval = 2
        static let max_queued_requests = 10
        static let max_retry_attempts = 3
    }
    
    private(set) var relays: [Relay] = []
    private var handlers: [RelayHandler] = []
    private var request_queue: [QueuedRequest] = []
    private var seen: Set<String> = Set()
    private var counts: [String: UInt64] = [:]
    private var retry_attempts_per_relay: [URL: Int] = [:]

    var descriptors: [RelayDescriptor] {
        relays.map { $0.descriptor }
    }
    
    var num_connecting: Int {
        relays.reduce(0) { n, r in n + (r.connection.state == .connecting ? 1 : 0) }
    }

    private func remove_handler(sub_id: String) {
        self.handlers = handlers.filter { $0.sub_id != sub_id }
        print("removing \(sub_id) handler, current: \(handlers.count)")
    }

    func register_handler(sub_id: String, handler: @escaping (String, NostrConnectionEvent) -> ()) {
        guard !handlers.contains(where: { $0.sub_id == sub_id }) else {
            return  // don't add duplicate handlers
        }
        
        handlers.append(RelayHandler(sub_id: sub_id, callback: handler))
        print("registering \(sub_id) handler, current: \(self.handlers.count)")
    }
    
    func remove_relay(_ relay_id: String) {
        disconnect(from: [relay_id])
        
        if let index = relays.firstIndex(where: { $0.id == relay_id }) {
            relays.remove(at: index)
        }
    }
    
    func add_relay(_ url: URL, info: RelayInfo) throws {
        let relay_id = get_relay_id(url)
        if get_relay(relay_id) != nil {
            throw RelayError.RelayAlreadyExists
        }
        let conn = RelayConnection(url: url) { event in
            self.handle_event(relay_id: relay_id, event: event)
        }
        let descriptor = RelayDescriptor(url: url, info: info)
        let relay = Relay(descriptor: descriptor, connection: conn)
        self.relays.append(relay)
    }
    
    /// This is used to retry dead connections
    func connect_to_disconnected() {
        for relay in relays where !relay.is_broken && relay.connection.state != .connected {
            let c = relay.connection
            
            let is_connecting = c.state == .reconnecting || c.state == .connecting
            
            let retry_attempts = retry_attempts_per_relay[c.url] ?? 0
            
            let delay = pow(Constants.base_reconnect_delay, TimeInterval(retry_attempts + 1))   // the + 1 helps us avoid a 1-second delay for the first retry
            if is_connecting && (Date.now.timeIntervalSince1970 - c.last_connection_attempt) > delay {
                if retry_attempts > Constants.max_retry_attempts {
                    if c.state != .notConnected {
                        c.disconnect()
                        print("exceeded max connection attempts with \(relay.descriptor.url.absoluteString)")
                        relay.mark_broken()
                    }
                    continue
                } else {
                    print("stale connection detected (\(relay.descriptor.url.absoluteString)). retrying after \(delay) seconds...")
                    c.connect(force: true)
                    retry_attempts_per_relay[c.url] = retry_attempts + 1
                }
            } else if is_connecting {
                continue
            } else {
                c.reconnect()
            }
        }
    }
    
    func reconnect(to relay_ids: [String]? = nil) {
        let relays: [Relay]
        if let relay_ids {
            relays = get_relays(relay_ids)
        } else {
            relays = self.relays
        }
        
        for relay in relays where !relay.is_broken {
            // don't try to reconnect to broken relays
            relay.connection.reconnect()
        }
    }
    
    func mark_broken(_ relay_id: String) {
        relays.first(where: { $0.id == relay_id })?.mark_broken()
    }

    func connect(to: [String]? = nil) {
        let relays = to.map{ get_relays($0) } ?? self.relays
        for relay in relays {
            relay.connection.connect()
        }
    }

    private func disconnect(from: [String]? = nil) {
        let relays = from.map{ get_relays($0) } ?? self.relays
        for relay in relays {
            relay.connection.disconnect()
        }
    }
    
    func unsubscribe(sub_id: String, to: [String]? = nil) {
        if to == nil {
            remove_handler(sub_id: sub_id)
        }
        send(.unsubscribe(sub_id), to: to)
    }
    
    func subscribe_to(sub_id: String, filters: [NostrFilter], to: [String]? = nil, handler: @escaping (String, NostrConnectionEvent) -> ()) {
        register_handler(sub_id: sub_id, handler: handler)
        send(.subscribe(.init(filters: filters, sub_id: sub_id)), to: to)
    }
    
    private func count_queued(relay: String) -> Int {
        request_queue.filter({ $0.relay == relay }).count
    }
    
    func queue_req(r: NostrRequest, relay: String) {
        let count = count_queued(relay: relay)
        guard count <= Constants.max_queued_requests else {
            print("can't queue, too many queued events for \(relay)")
            return
        }
        
        print("queueing request: \(r) for \(relay)")
        request_queue.append(QueuedRequest(req: r, relay: relay))
    }
    
    func send(_ req: NostrRequest, to: [String]? = nil) {
        let relays = to.map { get_relays($0) } ?? self.relays
        
        for relay in relays {
            guard relay.connection.state == .connected else {
                queue_req(r: req, relay: relay.id)
                continue
            }
            
            relay.connection.send(req)
        }
    }
    
    func get_relays(_ ids: [String]) -> [Relay] {
        relays.filter { ids.contains($0.id) }
    }
    
    func get_relay(_ id: String) -> Relay? {
        relays.first(where: { $0.id == id })
    }
    
    func record_last_pong(relay_id: String, event: NostrConnectionEvent) {
        if case .ws_event(let ws_event) = event {
            if case .pong = ws_event {
                if let relay = relays.first(where: { $0.id == relay_id }) {
                    relay.last_pong = UInt32(Date.now.timeIntervalSince1970)
                }
            }
        }
    }
    
    private func run_queue(_ relay_id: String) {
        self.request_queue = request_queue.reduce(into: Array<QueuedRequest>()) { (q, req) in
            guard req.relay == relay_id else {
                q.append(req)
                return
            }
            
            print("running queueing request: \(req.req) for \(relay_id)")
            self.send(req.req, to: [relay_id])
        }
    }
    
    private func record_seen(relay_id: String, event: NostrConnectionEvent) {
        if case .nostr_event(let ev) = event {
            if case .event(_, let nev) = ev {
                let k = relay_id + nev.id
                if !seen.contains(k) {
                    seen.insert(k)
                    let prev_count = counts[relay_id] ?? 0
                    counts[relay_id] = prev_count + 1
                }
            }
        }
    }
    
    private func handle_event(relay_id: String, event: NostrConnectionEvent) {
        record_last_pong(relay_id: relay_id, event: event)
        record_seen(relay_id: relay_id, event: event)
        
        // run req queue when we reconnect
        if case .ws_event(let ws) = event {
            if case .connected = ws {
                run_queue(relay_id)
            }
        }
        
        // handle reconnect logic, etc?
        for handler in handlers {
            handler.callback(relay_id, event)
        }
    }
}

func add_rw_relay(_ pool: RelayPool, _ url: String) {
    let url_ = URL(string: url)!
    try? pool.add_relay(url_, info: RelayInfo.rw)
}
