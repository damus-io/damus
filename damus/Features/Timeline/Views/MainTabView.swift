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

/// The unread-events hint on a timeline's tab bar item.
///
/// This supplies the whole `.tabItem`: the tab's icon, plus a small purple dot
/// when that timeline has unread events.
///
/// This is a `ViewModifier` rather than a plain `View` extension because it has
/// to observe ``NotificationStatusModel``. `ContentView` holds its `HomeModel`
/// as a plain property, so without an `@ObservedObject` somewhere in the view
/// graph the hint would never update — the custom `TabButton` observed the same
/// model for the same reason.
///
/// ``NotificationStatusModel/new_events`` is a `NewEventsBits` bitfield rather
/// than a count, so the hint is a dot and not a number. Surfacing real counts
/// would mean new per-timeline counters in the model, and the bit-set sites
/// dedupe on last-seen-event timestamps, so any count derived from them would
/// undercount.
///
/// ## Why the dot is drawn into the icon instead of using `.badge`
///
/// `View.badge(_:)` is the native-looking answer and is what this used through
/// build 1337, with a blank `Text` for a label. A TestFlight report said the
/// result was a solid red disc roughly as wide as the icon itself, and measuring
/// it on an iOS 26.5 simulator says why: **a tab bar badge has a fixed minimum
/// size of about 18pt** — the height a numeric badge needs — and no label or
/// font gets it below that. Every one of these renders the same 55x55px disc at
/// 3x, i.e. the bug:
///
/// - `Text(verbatim: " ")`, the old label. The space's advance width is not the
///   problem; the badge never sized itself to the label at all.
/// - `Text(verbatim: "")` and `Text(verbatim: "\u{200B}")`. A genuinely empty or
///   zero-width label neither shrinks the badge nor suppresses it.
/// - `Text(verbatim: " ").font(.system(size: 1))`. `.badge` ignores the label's
///   font.
/// - `badgeTextAttributes` with a 1pt font, both on `UITabBarItem.appearance()`
///   and on the tab bar's own `UITabBarAppearance`. Not smaller (55 -> 59px),
///   and it reaches into the global appearance state Liquid Glass styles.
///
/// `.badgeProminence(.decreased)` is iOS 17+, below our floor, and adjusts
/// colour rather than size.
///
/// An `.overlay` on the icon inside `.tabItem` does not work either: SwiftUI
/// takes only the `Image` and `Text` out of a tab item's content and drops
/// everything else, so the overlay never draws. That is also why the dot the
/// custom `TabButton` used to place with `alignmentGuide` offsets could not
/// simply be moved onto the system tab bar's items when it took them over.
///
/// What the tab bar does honour is the item's image, so the dot is composited
/// into it at ``dot_diameter`` against a 24pt icon. The canvas grows by half a
/// dot on every side so the icon stays centred where the tab bar puts it.
///
/// ## What compositing costs
///
/// A template image is a mask — everything in it takes the item's tint — so a
/// dot drawn into one comes out black or white rather than its own colour. The
/// composited image therefore has to be `.alwaysOriginal`, which also opts it
/// out of
/// the tint the tab bar would have applied, so this reproduces that tint by
/// hand: the `AccentColor` asset when the tab is selected and `UIColor.label`
/// when it is not, both matched against the system's own rendering. To keep that
/// approximation from mattering when it need not, a tab with no unread events
/// keeps the plain template asset and the system's own tinting; only a tab
/// actually showing a dot uses the composited image.
///
/// The dot is `DamusPurple`, which is also what the old hand-drawn `Circle`
/// used. The native badge could only ever be the system notification red —
/// recolouring it meant reaching into `UITabBarAppearance`, the same global
/// appearance state Liquid Glass styles — so drawing the dot ourselves is what
/// makes the brand colour available again.
///
/// Note that `DamusPurple` and `AccentColor` currently hold the same value, so
/// on the *selected* tab the dot matches the icon it sits beside; it stays
/// legible because the dot is solid and the icons are strokes. Should that stop
/// reading as a hint, this is the place to give the dot its own colour.
struct TimelineTabItem: ViewModifier {
    let timeline: Timeline
    @ObservedObject var notification_status: NotificationStatusModel
    let settings: UserSettingsStore
    /// Whether this is the tab the tab bar is currently showing.
    ///
    /// Needed because a composited icon has to reproduce the tint the tab bar
    /// applies to a template image, and that tint depends on selection.
    let is_selected: Bool

    @Environment(\.colorScheme) private var color_scheme

    /// The diameter of the unread dot, in points, against a 24pt tab icon.
    ///
    /// Small enough to read as a hint, which the ~18pt native badge did not.
    private static let dot_diameter: CGFloat = 8

    func body(content: Content) -> some View {
        content.tabItem {
            self.tab_icon
                .accessibilityLabel(self.accessibility_label)
        }
    }

    /// Whether this timeline has unread events the user wants indicated.
    private var has_unread: Bool {
        show_indicator(
            timeline: self.timeline,
            current: self.notification_status.new_events,
            indicator_setting: self.settings.notification_indicators
        )
    }

    /// The plain template asset, or the composited icon-plus-dot when unread.
    private var tab_icon: Image {
        guard self.has_unread, let dotted = self.dotted_tab_image else {
            return Image(self.timeline.tab_image)
        }

        return Image(uiImage: dotted)
    }

    /// The tab's icon with the unread dot drawn at its top trailing corner.
    ///
    /// `nil` if the asset is missing, which leaves ``tab_icon`` on the plain
    /// asset rather than dropping the tab item altogether.
    private var dotted_tab_image: UIImage? {
        guard let base = UIImage(named: self.timeline.tab_image) else { return nil }

        let dot = Self.dot_diameter
        let inset = dot / 2
        let canvas = CGSize(width: base.size.width + dot, height: base.size.height + dot)
        // A composited image is resolved once, here, rather than per trait
        // collection at draw time, so the dynamic colours have to be resolved
        // against the scheme this view was rendered for. Reading it from the
        // environment is also what re-renders us when the scheme changes.
        let traits = UITraitCollection(
            userInterfaceStyle: self.color_scheme == .dark ? .dark : .light
        )
        // `AccentColor` is the asset SwiftUI tints the selected item with. The
        // fallback is the unselected colour rather than `UIColor.tintColor`,
        // which resolves to the system blue away from a view hierarchy.
        let tint = (self.is_selected ? UIColor(named: "AccentColor") ?? .label : .label)
            .resolvedColor(with: traits)

        return UIGraphicsImageRenderer(size: canvas).image { context in
            base.withTintColor(tint, renderingMode: .alwaysOriginal)
                .draw(in: CGRect(origin: CGPoint(x: inset, y: inset), size: base.size))

            // Falls back to `systemPurple` so a missing asset stays in the same
            // family rather than reverting to the notification red this
            // deliberately moved away from.
            (UIColor(named: "DamusPurple") ?? .systemPurple)
                .resolvedColor(with: traits).setFill()
            context.cgContext.fillEllipse(
                in: CGRect(x: canvas.width - dot, y: 0, width: dot, height: dot)
            )
        }
        .withRenderingMode(.alwaysOriginal)
    }

    /// The tab's VoiceOver label, noting unread events when the dot is showing.
    ///
    /// The dot is part of an image, so without this it is invisible to
    /// VoiceOver.
    private var accessibility_label: String {
        let label = self.timeline.tab_accessibility_label
        guard self.has_unread else { return label }

        return String(
            format: NSLocalizedString(
                "%@, unread",
                comment: "Accessibility label for a tab bar tab that has unread events. The placeholder is the tab's own name, e.g. 'Home'."
            ),
            label
        )
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
        // A private reply is a reply: it answers a note of ours and belongs in the thread it
        // answers, not in the DM list, which has no thread to put it in and would file it under a
        // conversation that does not exist.
        case .like, .mention, .reply, .private_reply, .tagged, .repost, .zap, .profile_zap:
            return .notifications
        }
    }
}
