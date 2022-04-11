//
//  RelayPool.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation

class RelayPool {
    var relays: [Relay] = []
    let custom_handle_event: (String, NostrConnectionEvent) -> ()

    init(handle_event: @escaping (String, NostrConnectionEvent) -> ()) {
        self.custom_handle_event = handle_event
    }

    func add_relay(_ url: URL, info: RelayInfo) throws {
        let relay_id = get_relay_id(url)
        if get_relay(relay_id) != nil {
            throw RelayError.RelayAlreadyExists
        }
        let conn = RelayConnection(url: url) { event in
            self.handle_event(relay_id: relay_id, event: event)
        }
        let relay = Relay(url: url, info: info, connection: conn)
        self.relays.append(relay)
    }

    func connect(to: [String]? = nil) {
        let relays = to.map{ get_relays($0) } ?? self.relays
        for relay in relays {
            relay.connection.connect()
        }
    }

    func send(filters: [NostrFilter], sub_id: String, to: [String]? = nil) {
        let relays = to.map{ get_relays($0) } ?? self.relays

        for relay in relays {
            if relay.connection.isConnected {
                relay.connection.send(filters, sub_id: sub_id)
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
        custom_handle_event(relay_id, event)
    }
}

func add_rw_relay(_ pool: RelayPool, _ url: String) {
    let url_ = URL(string: url)!
    try! pool.add_relay(url_, info: RelayInfo.rw)
}

