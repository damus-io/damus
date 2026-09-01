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

/// The unread-events badge on a timeline's tab bar item.
///
/// The system tab bar owns its items, so the dot the custom `TabButton` used to
/// overlay with `alignmentGuide` offsets is gone. `View.badge(_:)` is the native
/// equivalent: it is `@available(iOS 15.0, ...)` and applies to a `TabView`
/// child that carries a `.tabItem`, so it needs neither the iOS 18+ `Tab` struct
/// nor an availability guard.
///
/// This is a `ViewModifier` rather than a plain `View` extension because it has
/// to observe ``NotificationStatusModel``. `ContentView` holds its `HomeModel`
/// as a plain property, so without an `@ObservedObject` somewhere in the view
/// graph the badge would never update — the custom `TabButton` observed the same
/// model for the same reason.
///
/// ``NotificationStatusModel/new_events`` is a `NewEventsBits` bitfield rather
/// than a count, and there is no native plain-dot badge — `.badge` takes an
/// `Int`, `Text` or string. A blank `Text` gets us the dot anyway: the badge
/// sizes itself to its empty label and the system draws it as a bare round dot,
/// which is what the old overlay drew. Surfacing real counts instead would mean
/// new per-timeline counters in the model, and the bit-set sites dedupe on
/// last-seen-event timestamps, so any count derived from them would undercount.
///
/// One deliberate visual difference from the old overlay: the system badge is
/// the standard notification red rather than the accent purple the hand-drawn
/// `Circle` used. Recolouring it means reaching into `UITabBarAppearance`, which
/// is the same global appearance state Liquid Glass styles, so we take the
/// native colour.
struct TimelineTabBadge: ViewModifier {
    let timeline: Timeline
    @ObservedObject var notification_status: NotificationStatusModel
    let settings: UserSettingsStore

    func body(content: Content) -> some View {
        content.badge(self.badge_label)
    }

    /// A blank label when this tab has unread events, `nil` (no badge) otherwise.
    private var badge_label: Text? {
        guard show_indicator(
            timeline: self.timeline,
            current: self.notification_status.new_events,
            indicator_setting: self.settings.notification_indicators
        ) else {
            return nil
        }

        return Text(verbatim: " ")
    }
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
