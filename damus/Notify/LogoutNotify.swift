//
//  LogoutNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct LogoutNotify: Notify {
    typealias Payload = ()
    var payload: ()
}

extension NotifyHandler {
    static var logout: NotifyHandler<LogoutNotify> {
        .init()
    }
}

extension Notifications {
    /// Sign out of damus. Goes back to the login screen.
    static var logout: Notifications<LogoutNotify> {
        .init(.init(payload: ()))
    }
}
