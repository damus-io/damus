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
    let callback: (String, NostrConnectionEvent) -> ()
}

struct QueuedRequest {
    let req: NostrRequestType
    let relay: String
    let skip_ephemeral: Bool
}

struct SeenEvent: Hashable {
    let relay_id: String
    let evid: String
}

class RelayPool {
    var relays: [Relay] = []
    var handlers: [RelayHandler] = []
    var request_queue: [QueuedRequest] = []
    var seen: Set<SeenEvent> = Set()
    var counts: [String: UInt64] = [:]
    
    private let network_monitor = NWPathMonitor()
    private let network_monitor_queue = DispatchQueue(label: "io.damus.network_monitor")
    private var last_network_status: NWPath.Status = .unsatisfied

    init() {
        network_monitor.pathUpdateHandler = { [weak self] path in
            if (path.status == .satisfied || path.status == .requiresConnection) && self?.last_network_status != path.status {
                DispatchQueue.main.async {
                    self?.connect_to_disconnected()
                }
            }
            
            if let self, path.status != self.last_network_status {
                for relay in self.relays {
                    relay.connection.log?.add("Network state: \(path.status)")
                }
            }
            
            self?.last_network_status = path.status
        }
        network_monitor.start(queue: network_monitor_queue)
    }
    
    var our_descriptors: [RelayDescriptor] {
        return all_descriptors.filter { d in !d.ephemeral }
    }
    
    var all_descriptors: [RelayDescriptor] {
        relays.map { r in r.descriptor }
    }
    
    var num_connected: Int {
        return relays.reduce(0) { n, r in n + (r.connection.isConnected ? 1 : 0) }
    }

    func remove_handler(sub_id: String) {
        self.handlers = handlers.filter { $0.sub_id != sub_id }
        print("removing \(sub_id) handler, current: \(handlers.count)")
    }
    
    func ping() {
        for relay in relays {
            relay.connection.ping()
        }
    }
    
    func register_handler(sub_id: String, handler: @escaping (String, NostrConnectionEvent) -> ()) {
        for handler in handlers {
            // don't add duplicate handlers
            if handler.sub_id == sub_id {
                return
            }
        }
        self.handlers.append(RelayHandler(sub_id: sub_id, callback: handler))
        print("registering \(sub_id) handler, current: \(self.handlers.count)")
    }
    
    func remove_relay(_ relay_id: String) {
        var i: Int = 0
        
        self.disconnect(to: [relay_id])
        
        for relay in relays {
            if relay.id == relay_id {
                relays.remove(at: i)
                break
            }
            
            i += 1
        }
    }
    
    func add_relay(_ desc: RelayDescriptor) throws {
        let url = desc.url
        let relay_id = get_relay_id(url)
        if get_relay(relay_id) != nil {
            throw RelayError.RelayAlreadyExists
        }
        let conn = RelayConnection(url: url) { event in
            self.handle_event(relay_id: relay_id, event: event)
        }
        let relay = Relay(descriptor: desc, connection: conn)
        self.relays.append(relay)
    }
    
    func setLog(_ log: RelayLog, for relay_id: String) {
        // add the current network state to the log
        log.add("Network state: \(network_monitor.currentPath.status)")
        
        get_relay(relay_id)?.connection.log = log
    }
    
    /// This is used to retry dead connections
    func connect_to_disconnected() {
        for relay in relays {
            let c = relay.connection
            
            let is_connecting = c.isConnecting
            
            if is_connecting && (Date.now.timeIntervalSince1970 - c.last_connection_attempt) > 5 {
                print("stale connection detected (\(relay.descriptor.url.url.absoluteString)). retrying...")
                relay.connection.reconnect()
            } else if relay.is_broken || is_connecting || c.isConnected {
                continue
            } else {
                relay.connection.reconnect()
            }
            
        }
    }
    
    func reconnect(to: [String]? = nil) {
        let relays = to.map{ get_relays($0) } ?? self.relays
        for relay in relays {
            // don't try to reconnect to broken relays
            relay.connection.reconnect()
        }
    }

    func connect(to: [String]? = nil) {
        let relays = to.map{ get_relays($0) } ?? self.relays
        for relay in relays {
            relay.connection.connect()
        }
    }

    func disconnect(to: [String]? = nil) {
        let relays = to.map{ get_relays($0) } ?? self.relays
        for relay in relays {
            relay.connection.disconnect()
        }
    }
    
    func unsubscribe(sub_id: String, to: [String]? = nil) {
        if to == nil {
            self.remove_handler(sub_id: sub_id)
        }
        self.send(.unsubscribe(sub_id), to: to)
    }
    
    func subscribe(sub_id: String, filters: [NostrFilter], handler: @escaping (String, NostrConnectionEvent) -> (), to: [String]? = nil) {
        register_handler(sub_id: sub_id, handler: handler)
        send(.subscribe(.init(filters: filters, sub_id: sub_id)), to: to)
    }
    
    func subscribe_to(sub_id: String, filters: [NostrFilter], to: [String]?, handler: @escaping (String, NostrConnectionEvent) -> ()) {
        register_handler(sub_id: sub_id, handler: handler)
        send(.subscribe(.init(filters: filters, sub_id: sub_id)), to: to)
    }
    
    func count_queued(relay: String) -> Int {
        var c = 0
        for request in request_queue {
            if request.relay == relay {
                c += 1
            }
        }
        
        return c
    }
    
    func queue_req(r: NostrRequestType, relay: String, skip_ephemeral: Bool) {
        let count = count_queued(relay: relay)
        guard count <= 10 else {
            print("can't queue, too many queued events for \(relay)")
            return
        }
        
        print("queueing request for \(relay)")
        request_queue.append(QueuedRequest(req: r, relay: relay, skip_ephemeral: skip_ephemeral))
    }
    
    func send_raw(_ req: NostrRequestType, to: [String]? = nil, skip_ephemeral: Bool = true) {
        let relays = to.map{ get_relays($0) } ?? self.relays

        for relay in relays {
            if req.is_read && !(relay.descriptor.info.read ?? true) {
                continue
            }
            
            if req.is_write && !(relay.descriptor.info.write ?? true) {
                continue
            }
            
            if relay.descriptor.ephemeral && skip_ephemeral {
                continue
            }
            
            guard relay.connection.isConnected else {
                queue_req(r: req, relay: relay.id, skip_ephemeral: skip_ephemeral)
                continue
            }
            
            relay.connection.send(req)
        }
    }
    
    func send(_ req: NostrRequest, to: [String]? = nil, skip_ephemeral: Bool = true) {
        send_raw(.typical(req), to: to, skip_ephemeral: skip_ephemeral)
    }
    
    func get_relays(_ ids: [String]) -> [Relay] {
        // don't include ephemeral relays in the default list to query
        relays.filter { ids.contains($0.id) }
    }
    
    func get_relay(_ id: String) -> Relay? {
        relays.first(where: { $0.id == id })
    }
    
    func run_queue(_ relay_id: String) {
        self.request_queue = request_queue.reduce(into: Array<QueuedRequest>()) { (q, req) in
            guard req.relay == relay_id else {
                q.append(req)
                return
            }
            
            print("running queueing request: \(req.req) for \(relay_id)")
            self.send_raw(req.req, to: [relay_id], skip_ephemeral: false)
        }
    }
    
    func record_seen(relay_id: String, event: NostrConnectionEvent) {
        if case .nostr_event(let ev) = event {
            if case .event(_, let nev) = ev {
                let k = SeenEvent(relay_id: relay_id, evid: nev.id)
                if !seen.contains(k) {
                    seen.insert(k)
                    if counts[relay_id] == nil {
                        counts[relay_id] = 1
                    } else {
                        counts[relay_id] = (counts[relay_id] ?? 0) + 1
                    }
                }
            }
        }
    }
    
    func handle_event(relay_id: String, event: NostrConnectionEvent) {
        record_seen(relay_id: relay_id, event: event)
        
        // run req queue when we reconnect
        if case .ws_event(let ws) = event {
            if case .connected = ws {
                run_queue(relay_id)
            }
        }
        
        for handler in handlers {
            handler.callback(relay_id, event)
        }
    }
}

func add_rw_relay(_ pool: RelayPool, _ url: String) {
    guard let url = RelayURL(url) else {
        return
    }
    try? pool.add_relay(RelayDescriptor(url: url, info: .rw))
}


