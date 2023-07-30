//
//  ScrollToTopNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct ScrollToTopNotify: Notify {
    typealias Payload = ()
    var payload: ()
}

extension NotifyHandler {
    static var scroll_to_top: NotifyHandler<ScrollToTopNotify> {
        .init()
    }
}

extension Notifications {
    static var scroll_to_top: Notifications<ScrollToTopNotify> {
        .init(.init(payload: ()))
    }
}
