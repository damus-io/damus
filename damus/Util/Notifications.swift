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
    static var relays_changed: Notification.Name {
        return Notification.Name("relays_changed")
    }
    static var select_event: Notification.Name {
        return Notification.Name("select_event")
    }
    static var select_quote: Notification.Name {
        return Notification.Name("select quote")
    }
    static var reply: Notification.Name {
        return Notification.Name("reply")
    }
    static var profile_updated: Notification.Name {
        return Notification.Name("profile_updated")
    }
    static var switched_timeline: Notification.Name {
        return Notification.Name("switched_timeline")
    }
    static var liked: Notification.Name {
        return Notification.Name("liked")
    }
    static var open_profile: Notification.Name {
        return Notification.Name("open_profile")
    }
    static var scroll_to_top: Notification.Name {
        return Notification.Name("scroll_to_to")
    }
    static var broadcast_event: Notification.Name {
        return Notification.Name("broadcast event")
    }
    static var open_thread: Notification.Name {
        return Notification.Name("open thread")
    }
    static var notice: Notification.Name {
        return Notification.Name("notice")
    }
    static var like: Notification.Name {
        return Notification.Name("like note")
    }
    static var delete: Notification.Name {
        return Notification.Name("delete note")
    }
    static var post: Notification.Name {
        return Notification.Name("send post")
    }
    static var boost: Notification.Name {
        return Notification.Name("boost")
    }
    static var boosted: Notification.Name {
        return Notification.Name("boosted")
    }
    static var follow: Notification.Name {
        return Notification.Name("follow")
    }
    static var unfollow: Notification.Name {
        return Notification.Name("unfollow")
    }
    static var login: Notification.Name {
        return Notification.Name("login")
    }
    static var logout: Notification.Name {
        return Notification.Name("logout")
    }
    static var followed: Notification.Name {
        return Notification.Name("followed")
    }
    static var chatroom_meta: Notification.Name {
        return Notification.Name("chatroom_meta")
    }
    static var unfollowed: Notification.Name {
        return Notification.Name("unfollowed")
    }
    static var report: Notification.Name {
        return Notification.Name("report")
    }
    static var block: Notification.Name {
        return Notification.Name("block")
    }
    static var new_mutes: Notification.Name {
        return Notification.Name("new_mutes")
    }
    static var new_unmutes: Notification.Name {
        return Notification.Name("new_unmutes")
    }
    static var deleted_account: Notification.Name {
        return Notification.Name("deleted_account")
    }
}

func handle_notify(_ name: Notification.Name) -> NotificationCenter.Publisher {
    return NotificationCenter.default.publisher(for: name)
}

func notify(_ name: NSNotification.Name, _ object: Any?) {
    NotificationCenter.default.post(name: name, object: object)
}
