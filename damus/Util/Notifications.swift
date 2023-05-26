//
//  Notifications.swift
//  damus
//
//  Created by William Casarin on 2022-04-22.
//

import Foundation

extension Notification.Name {
    static var relays_changed: Notification.Name {
        return Notification.Name("relays_changed")
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
    static var scroll_to_top: Notification.Name {
        return Notification.Name("scroll_to_to")
    }
    static var broadcast_event: Notification.Name {
        return Notification.Name("broadcast event")
    }
    static var notice: Notification.Name {
        return Notification.Name("notice")
    }
    static var delete: Notification.Name {
        return Notification.Name("delete note")
    }
    static var post: Notification.Name {
        return Notification.Name("send post")
    }
    static var compose: Notification.Name {
        return Notification.Name("compose")
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
    static var unfollowed: Notification.Name {
        return Notification.Name("unfollowed")
    }
    static var report: Notification.Name {
        return Notification.Name("report")
    }
    static var mute: Notification.Name {
        return Notification.Name("mute")
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
    static var update_stats: Notification.Name {
        return Notification.Name("update_stats")
    }
    static var zapping: Notification.Name {
        return Notification.Name("zapping")
    }
    static var mute_thread: Notification.Name {
        return Notification.Name("mute_thread")
    }
    static var unmute_thread: Notification.Name {
        return Notification.Name("unmute_thread")
    }
    static var local_notification: Notification.Name {
        return Notification.Name("local_notification")
    }
    static var onlyzaps_mode: Notification.Name {
        return Notification.Name("hide_reactions")
    }
    static var attached_wallet: Notification.Name {
        return Notification.Name("attached_wallet")
    }
}

func handle_notify(_ name: Notification.Name) -> NotificationCenter.Publisher {
    return NotificationCenter.default.publisher(for: name)
}

func notify(_ name: NSNotification.Name, _ object: Any?) {
    NotificationCenter.default.post(name: name, object: object)
}
