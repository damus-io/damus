//
//  ReconnectRelaysNotify.swift
//  damus
//
//  Created by Charlie Fish on 12/18/23.
//

import Foundation

struct ReconnectRelaysNotify: Notify {
    typealias Payload = ()
    var payload: ()
}

extension NotifyHandler {
    static var disconnect_relays: NotifyHandler<ReconnectRelaysNotify> {
        .init()
    }
}

extension Notifications {
    /// Reconnects all relays.
    static var disconnect_relays: Notifications<ReconnectRelaysNotify> {
        .init(.init(payload: ()))
    }
}
