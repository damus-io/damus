//
//  MainTabView.swift
//  damus
//
//  Created by William Casarin on 2022-05-19.
//

import SwiftUI

enum Timeline: String, CustomStringConvertible, Hashable {
    case home
    case vines
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
    
struct TabButton: View {
    let timeline: Timeline
    let img: String
    @Binding var selected: Timeline
    @ObservedObject var nstatus: NotificationStatusModel
    
    let settings: UserSettingsStore
    let action: (Timeline) -> ()
    
    var body: some View {
        ZStack(alignment: .center) {
            Tab
            
            if show_indicator(timeline: timeline, current: nstatus.new_events, indicator_setting: settings.notification_indicators) {
                Circle()
                    .size(CGSize(width: 8, height: 8))
                    .frame(width: 10, height: 10, alignment: .topTrailing)
                    .alignmentGuide(VerticalAlignment.center) { a in a.height + 2.0 }
                    .alignmentGuide(HorizontalAlignment.center) { a in a.width - 12.0 }
                    .foregroundColor(.accentColor)
            }
        }
    }
    
    var Tab: some View {
        Button(action: {
            action(timeline)
            let bits = timeline_to_notification_bits(timeline, ev: nil)
            nstatus.new_events = NewEventsBits(rawValue: nstatus.new_events.rawValue & ~bits.rawValue)
        }) {
            Image(selected != timeline ? img : "\(img).fill")
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, minHeight: 30.0)
        }
        .foregroundColor(.primary)
    }
}
    

struct TabBar: View {
    var nstatus: NotificationStatusModel
    var navIsAtRoot: Bool
    @Binding var selected: Timeline
    @Binding var headerOffset: CGFloat
    
    let settings: UserSettingsStore
    let action: (Timeline) -> ()
    
    var body: some View {
        VStack {
            Divider()
            HStack {
                TabButton(timeline: .home, img: "home", selected: $selected, nstatus: nstatus, settings: settings, action: action).keyboardShortcut("1")
                if settings.enable_vine_feature {
                    TabButton(timeline: .vines, img: "vine", selected: $selected, nstatus: nstatus, settings: settings, action: action).keyboardShortcut("2")
                }
                TabButton(timeline: .search, img: "search", selected: $selected, nstatus: nstatus, settings: settings, action: action).keyboardShortcut("3")
                TabButton(timeline: .notifications, img: "notification-bell", selected: $selected, nstatus: nstatus, settings: settings, action: action).keyboardShortcut("4")
            }
        }
        .opacity(selected != .home || (selected == .home && !navIsAtRoot) ? 1.0 : 0.35 + abs(1.25 - (abs(headerOffset/100.0))))
    }
}
