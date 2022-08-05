//
//  RelayPool.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation

struct SubscriptionId: Identifiable, CustomStringConvertible {
    let id: String

    var description: String {
        id
    }
}

struct RelayId: Identifiable, CustomStringConvertible {
    let id: String

    var description: String {
        id
    }
}

struct RelayHandler {
    let sub_id: String
    let callback: (String, NostrConnectionEvent) -> ()
}

class RelayPool {
    var relays: [Relay] = []
    var handlers: [RelayHandler] = []

    var descriptors: [RelayDescriptor] {
        relays.map { $0.descriptor }
    }
    
    var num_connecting: Int {
        return relays.reduce(0) { n, r in n + (r.connection.isConnecting ? 1 : 0) }
    }

    func remove_handler(sub_id: String) {
        handlers = handlers.filter { $0.sub_id != sub_id }
    }

    func register_handler(sub_id: String, handler: @escaping (String, NostrConnectionEvent) -> ()) {
        
        self.handlers.append(RelayHandler(sub_id: sub_id, callback: handler))
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
        for relay in relays {
            if !relay.connection.isConnected && !relay.connection.isConnecting {
                relay.connection.connect()
            }
        }
    }
    
    func reconnect(to: [String]? = nil) {
        let relays = to.map{ get_relays($0) } ?? self.relays
        for relay in relays {
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
        self.remove_handler(sub_id: sub_id)
        self.send(.unsubscribe(sub_id))
    }
    
    func subscribe(sub_id: String, filters: [NostrFilter], handler: @escaping (String, NostrConnectionEvent) -> ()) {
        register_handler(sub_id: sub_id, handler: handler)
        send(.subscribe(.init(filters: filters, sub_id: sub_id)))
    }
    
    func subscribe_to(sub_id: String, filters: [NostrFilter], to: [String]?, handler: @escaping (String, NostrConnectionEvent) -> ()) {
        register_handler(sub_id: sub_id, handler: handler)
        send(.subscribe(.init(filters: filters, sub_id: sub_id)), to: to)
    }
    
    func send(_ req: NostrRequest, to: [String]? = nil) {
        let relays = to.map{ get_relays($0) } ?? self.relays

        for relay in relays {
            if relay.connection.isConnected {
                relay.connection.send(req)
            }
        }
    }

    func get_relays(_ ids: [String]) -> [Relay] {
        var relays: [Relay] = []

        for id in ids {
            if let relay = get_relay(id) {
                relays.append(relay)
            }
        }

        return relays
    }

    func get_relay(_ id: String) -> Relay? {
        for relay in relays {
            if relay.id == id {
                return relay
            }
        }

        return nil
    }

    func handle_event(relay_id: String, event: NostrConnectionEvent) {
        // handle reconnect logic, etc?
        for handler in handlers {
            handler.callback(relay_id, event)
        }
    }
}

func add_rw_relay(_ pool: RelayPool, _ url: String) {
    let url_ = URL(string: url)!
    try! pool.add_relay(url_, info: RelayInfo.rw)
}

