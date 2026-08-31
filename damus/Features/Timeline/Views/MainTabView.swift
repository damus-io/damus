//
//  MainTabView.swift
//  damus
//
//  Created by William Casarin on 2022-05-19.
//

import SwiftUI

enum Timeline: String, CustomStringConvertible, Hashable {
    case home
    case notifications
    case search
    case dms
    
    var description: String {
        return self.rawValue
    }
}

func show_indicator(timeline: Timeline, current: NewEventsBits, indicator_setting: Int) -> Bool {
    if timeline == .notifications {
        return (current.rawValue & indicator_setting & NewEventsBits.notifications.rawValue) > 0
    }
    return (current.rawValue & indicator_setting) == timeline_to_notification_bits(timeline, ev: nil).rawValue
}
    
extension Timeline {
    /// The tabs in the order they appear in the tab bar, left to right.
    static let tab_order: [Timeline] = [.home, .dms, .search, .notifications]

    /// The template image asset used for this tab's tab bar item.
    var tab_image: String {
        switch self {
        case .home: return "home"
        case .dms: return "messages"
        case .search: return "search"
        case .notifications: return "notification-bell"
        }
    }

    /// The keyboard shortcut that selects this tab.
    ///
    /// These used to live on the custom tab bar's buttons. A system tab bar
    /// gives us nowhere to hang them, so `ContentView` puts them on hidden
    /// buttons instead.
    var keyboard_shortcut: KeyEquivalent {
        switch self {
        case .home: return "1"
        case .dms: return "2"
        case .search: return "3"
        case .notifications: return "4"
        }
    }

    /// A VoiceOver label for this tab's tab bar item.
    ///
    /// The tab items are icon-only, so they carry no title for VoiceOver to read.
    var tab_accessibility_label: String {
        switch self {
        case .home:
            return NSLocalizedString("Home", comment: "Accessibility label for the home tab in the tab bar.")
        case .dms:
            return NSLocalizedString("Direct messages", comment: "Accessibility label for the direct messages tab in the tab bar.")
        case .search:
            return NSLocalizedString("Search", comment: "Accessibility label for the search tab in the tab bar.")
        case .notifications:
            return NSLocalizedString("Notifications", comment: "Accessibility label for the notifications tab in the tab bar.")
        }
    }
}

extension LocalNotificationType {
    /// The timeline tab a notification of this type belongs to.
    ///
    /// Each tab owns its own navigation stack, so opening a push notification
    /// has to pick the tab it semantically belongs to instead of pushing into
    /// whichever tab happens to be selected.
    ///
    /// This lives here rather than beside `LocalNotificationType` because
    /// `LocalNotification.swift` is also compiled into the notification service
    /// extension, which has no `Timeline`.
    var timeline: Timeline {
        switch self {
        case .dm:
            return .dms
        case .like, .mention, .reply, .tagged, .repost, .zap, .profile_zap:
            return .notifications
        }
    }
}
