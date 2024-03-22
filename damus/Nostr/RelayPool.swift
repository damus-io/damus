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
    let callback: (RelayURL, NostrConnectionEvent) -> ()
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

class RelayPool {
    var relays: [Relay] = []
    var handlers: [RelayHandler] = []
    var request_queue: [QueuedRequest] = []
    var seen: Set<SeenEvent> = Set()
    var counts: [RelayURL: UInt64] = [:]
    var ndb: Ndb
    var keypair: Keypair?
    var message_received_function: (((String, RelayDescriptor)) -> Void)?
    var message_sent_function: (((String, Relay)) -> Void)?

    private let network_monitor = NWPathMonitor()
    private let network_monitor_queue = DispatchQueue(label: "io.damus.network_monitor")
    private var last_network_status: NWPath.Status = .unsatisfied

    func close() {
        disconnect()
        relays = []
        handlers = []
        request_queue = []
        seen.removeAll()
        counts = [:]
        keypair = nil
    }

    init(ndb: Ndb, keypair: Keypair? = nil) {
        self.ndb = ndb
        self.keypair = keypair

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

    func register_handler(sub_id: String, handler: @escaping (RelayURL, NostrConnectionEvent) -> ()) {
        for handler in handlers {
            // don't add duplicate handlers
            if handler.sub_id == sub_id {
                return
            }
        }
        self.handlers.append(RelayHandler(sub_id: sub_id, callback: handler))
        print("registering \(sub_id) handler, current: \(self.handlers.count)")
    }

    func remove_relay(_ relay_id: RelayURL) {
        var i: Int = 0

        self.disconnect(to: [relay_id])
        
        for relay in relays {
            if relay.id == relay_id {
                relay.connection.disablePermanently()
                relays.remove(at: i)
                break
            }
            
            i += 1
        }
    }

    func add_relay(_ desc: RelayDescriptor) throws {
        let relay_id = desc.url
        if get_relay(relay_id) != nil {
            throw RelayError.RelayAlreadyExists
        }
        let conn = RelayConnection(url: desc.url, handleEvent: { event in
            self.handle_event(relay_id: relay_id, event: event)
        }, processEvent: { wsev in
            guard case .message(let msg) = wsev,
                  case .string(let str) = msg
            else { return }

            let _ = self.ndb.process_event(str)
            self.message_received_function?((str, desc))
        })
        let relay = Relay(descriptor: desc, connection: conn)
        self.relays.append(relay)
    }

    func setLog(_ log: RelayLog, for relay_id: RelayURL) {
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
                print("stale connection detected (\(relay.descriptor.url.absoluteString)). retrying...")
                relay.connection.reconnect()
            } else if relay.is_broken || is_connecting || c.isConnected {
                continue
            } else {
                relay.connection.reconnect()
            }
            
        }
    }

    func reconnect(to: [RelayURL]? = nil) {
        let relays = to.map{ get_relays($0) } ?? self.relays
        for relay in relays {
            // don't try to reconnect to broken relays
            relay.connection.reconnect()
        }
    }

    func connect(to: [RelayURL]? = nil) {
        let relays = to.map{ get_relays($0) } ?? self.relays
        for relay in relays {
            relay.connection.connect()
        }
    }

    func disconnect(to: [RelayURL]? = nil) {
        let relays = to.map{ get_relays($0) } ?? self.relays
        for relay in relays {
            relay.connection.disconnect()
        }
    }

    func unsubscribe(sub_id: String, to: [RelayURL]? = nil) {
        if to == nil {
            self.remove_handler(sub_id: sub_id)
        }
        self.send(.unsubscribe(sub_id), to: to)
    }

    func subscribe(sub_id: String, filters: [NostrFilter], handler: @escaping (RelayURL, NostrConnectionEvent) -> (), to: [RelayURL]? = nil) {
        register_handler(sub_id: sub_id, handler: handler)
        send(.subscribe(.init(filters: filters, sub_id: sub_id)), to: to)
    }

    func subscribe_to(sub_id: String, filters: [NostrFilter], to: [RelayURL]?, handler: @escaping (RelayURL, NostrConnectionEvent) -> ()) {
        register_handler(sub_id: sub_id, handler: handler)
        send(.subscribe(.init(filters: filters, sub_id: sub_id)), to: to)
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

    func send_raw(_ req: NostrRequestType, to: [RelayURL]? = nil, skip_ephemeral: Bool = true) {
        let relays = to.map{ get_relays($0) } ?? self.relays

        // send to local relay (nostrdb)
        switch req {
        case .typical(let r):
            if case .event = r, let rstr = make_nostr_req(r) {
                let _ = ndb.process_client_event(rstr)
            }
        case .custom(let string):
            let _ = ndb.process_client_event(string)
        }

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
            
            relay.connection.send(req, callback: { str in
                self.message_sent_function?((str, relay))
            })
        }
    }

    func send(_ req: NostrRequest, to: [RelayURL]? = nil, skip_ephemeral: Bool = true) {
        send_raw(.typical(req), to: to, skip_ephemeral: skip_ephemeral)
    }

    func get_relays(_ ids: [RelayURL]) -> [Relay] {
        // don't include ephemeral relays in the default list to query
        relays.filter { ids.contains($0.id) }
    }

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
            self.send_raw(req.req, to: [relay_id], skip_ephemeral: false)
        }
    }

    func record_seen(relay_id: RelayURL, event: NostrConnectionEvent) {
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

    func handle_event(relay_id: RelayURL, event: NostrConnectionEvent) {
        record_seen(relay_id: relay_id, event: event)

        // run req queue when we reconnect
        if case .ws_event(let ws) = event {
            if case .connected = ws {
                run_queue(relay_id)
            }
        }

        // Handle auth
        if case let .nostr_event(nostrResponse) = event,
           case let .auth(challenge_string) = nostrResponse {
            if let relay = get_relay(relay_id) {
                print("received auth request from \(relay.descriptor.url.id)")
                relay.authentication_state = .pending
                if let keypair {
                    if let fullKeypair = keypair.to_full() {
                        if let authRequest = make_auth_request(keypair: fullKeypair, challenge_string: challenge_string, relay: relay) {
                            send(.auth(authRequest), to: [relay_id], skip_ephemeral: false)
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
            handler.callback(relay_id, event)
        }
    }
}

func add_rw_relay(_ pool: RelayPool, _ url: RelayURL) {
    try? pool.add_relay(RelayDescriptor(url: url, info: .rw))
}


