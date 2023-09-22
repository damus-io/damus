//
//  OnlyZapsNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct OnlyZapsNotify: Notify {
    typealias Payload = Bool
    var payload: Bool
}

extension NotifyHandler {
    static var onlyzaps_mode: NotifyHandler<OnlyZapsNotify> {
        .init()
    }
}

extension Notifications {
    static func onlyzaps_mode(_ on: Bool) -> Notifications<OnlyZapsNotify> {
        .init(.init(payload: on))
    }
}
