//
//  NewMutesNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct NewMutesNotify: Notify {
    typealias Payload = Set<Pubkey>
    var payload: Payload
}

extension NotifyHandler {
    static var new_mutes: NotifyHandler<NewMutesNotify> {
        .init()
    }
}

extension Notifications {
    static func new_mutes(_ pubkeys: Set<Pubkey>) -> Notifications<NewMutesNotify> {
        .init(.init(payload: pubkeys))
    }
}
