//
//  Notifications.swift
//  damus
//
//  Created by William Casarin on 2022-04-22.
//

import Foundation

extension Notification.Name {
    static var thread_focus: Notification.Name {
        return Notification.Name("thread focus")
    }
}

extension Notification.Name {
    static var select_event: Notification.Name {
        return Notification.Name("select_event")
    }
}

extension Notification.Name {
    static var select_quote: Notification.Name {
        return Notification.Name("select quote")
    }
}

extension Notification.Name {
    static var broadcast_event: Notification.Name {
        return Notification.Name("broadcast event")
    }
}

extension Notification.Name {
    static var open_thread: Notification.Name {
        return Notification.Name("open thread")
    }
}

extension Notification.Name {
    static var post: Notification.Name {
        return Notification.Name("send post")
    }
}
