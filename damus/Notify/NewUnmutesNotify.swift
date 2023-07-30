//
//  NewUnmutesNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct NewUnmutesNotify: Notify {
    typealias Payload = Set<Pubkey>
    var payload: Payload
}

extension NotifyHandler {
    static var new_unmutes: NotifyHandler<NewUnmutesNotify> {
        .init()
    }
}

extension Notifications {
    static func new_unmutes(_ pubkeys: Set<Pubkey>) -> Notifications<NewUnmutesNotify> {
        .init(.init(payload: pubkeys))
    }
}
