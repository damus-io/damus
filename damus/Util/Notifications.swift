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
    static var reply: Notification.Name {
        return Notification.Name("reply")
    }
}

extension Notification.Name {
    static var profile_updated: Notification.Name {
        return Notification.Name("profile_updated")
    }
}

extension Notification.Name {
    static var switched_timeline: Notification.Name {
        return Notification.Name("switched_timeline")
    }
}

extension Notification.Name {
    static var liked: Notification.Name {
        return Notification.Name("liked")
    }
}

extension Notification.Name {
    static var open_profile: Notification.Name {
        return Notification.Name("open_profile")
    }
}

extension Notification.Name {
    static var scroll_to_top: Notification.Name {
        return Notification.Name("scroll_to_to")
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
    static var notice: Notification.Name {
        return Notification.Name("notice")
    }
}

extension Notification.Name {
    static var like: Notification.Name {
        return Notification.Name("like note")
    }
}

extension Notification.Name {
    static var delete: Notification.Name {
        return Notification.Name("delete note")
    }
}

extension Notification.Name {
    static var post: Notification.Name {
        return Notification.Name("send post")
    }
}

extension Notification.Name {
    static var boost: Notification.Name {
        return Notification.Name("boost")
    }
}

extension Notification.Name {
    static var boosted: Notification.Name {
        return Notification.Name("boosted")
    }
}

extension Notification.Name {
    static var follow: Notification.Name {
        return Notification.Name("follow")
    }
}

extension Notification.Name {
    static var unfollow: Notification.Name {
        return Notification.Name("unfollow")
    }
}

extension Notification.Name {
    static var login: Notification.Name {
        return Notification.Name("login")
    }
}

extension Notification.Name {
    static var logout: Notification.Name {
        return Notification.Name("logout")
    }
}

extension Notification.Name {
    static var followed: Notification.Name {
        return Notification.Name("followed")
    }
}

extension Notification.Name {
    static var chatroom_meta: Notification.Name {
        return Notification.Name("chatroom_meta")
    }
}

extension Notification.Name {
    static var unfollowed: Notification.Name {
        return Notification.Name("unfollowed")
    }
}

func handle_notify(_ name: Notification.Name) -> NotificationCenter.Publisher {
    return NotificationCenter.default.publisher(for: name)
}

func notify(_ name: NSNotification.Name, _ object: Any?) {
    NotificationCenter.default.post(name: name, object: object)
}
