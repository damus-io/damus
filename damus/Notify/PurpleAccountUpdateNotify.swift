//
//  PurpleAccountUpdateNotify.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-01-29.
//

import Foundation

struct PurpleAccountUpdateNotify: Notify {
    typealias Payload = DamusPurple.Account
    var payload: DamusPurple.Account
}

extension NotifyHandler {
    static var purple_account_update: NotifyHandler<PurpleAccountUpdateNotify> {
        .init()
    }
}

extension Notifications {
    static func purple_account_update(_ result: DamusPurple.Account) -> Notifications<PurpleAccountUpdateNotify> {
        .init(.init(payload: result))
    }
}
