//
//  ProfileNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct ProfileUpdatedNotify: Notify {
    typealias Payload = ProfileUpdate
    var payload: Payload
}

extension NotifyHandler {
    static var profile_updated: NotifyHandler<ProfileUpdatedNotify> {
        .init()
    }
}

extension Notifications {
    static func profile_updated(_ update: ProfileUpdate) -> Notifications<ProfileUpdatedNotify> {
        .init(.init(payload: update))
    }
}
