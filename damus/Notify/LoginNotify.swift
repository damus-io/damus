//
//  LoginNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct LoginNotify: Notify {
    typealias Payload = Keypair
    var payload: Keypair
}

extension NotifyHandler {
    static var login: NotifyHandler<LoginNotify> {
        .init()
    }
}

extension Notifications {
    static func login(_ keypair: Keypair) -> Notifications<LoginNotify> {
        .init(.init(payload: keypair))
    }
}
