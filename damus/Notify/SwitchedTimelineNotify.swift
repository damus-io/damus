//
//  SwitchedTimelineNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct SwitchedTimelineNotify: Notify {
    typealias Payload = Timeline
    var payload: Payload
}

extension NotifyHandler {
    static var switched_timeline: NotifyHandler<SwitchedTimelineNotify> {
        .init()
    }
}

extension Notifications {
    static func switched_timeline(_ timeline: Timeline) -> Notifications<SwitchedTimelineNotify> {
        .init(.init(payload: timeline))
    }
}
