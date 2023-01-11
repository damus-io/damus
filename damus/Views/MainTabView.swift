//
//  MainTabView.swift
//  damus
//
//  Created by William Casarin on 2022-05-19.
//

import SwiftUI

enum Timeline: String, CustomStringConvertible {
    case home
    case notifications
    case search
    case dms
    
    var description: String {
        return self.rawValue
    }
}

func timeline_bit(_ timeline: Timeline) -> Int {
    switch timeline {
    case .home: return 1 << 0
    case .notifications: return 1 << 1
    case .search: return 1 << 2
    case .dms: return 1 << 3
    }
}

    
struct TabButton: View {
    let timeline: Timeline
    let img: String
    @Binding var selected: Timeline?
    @Binding var new_events: NewEventsBits
    @Binding var isSidebarVisible: Bool
    
    let action: (Timeline) -> ()
    
    var body: some View {
        ZStack(alignment: .center) {
            Tab
            
            if new_events.is_set(timeline) {
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
            new_events = NewEventsBits(prev: new_events, unsetting: timeline)
            isSidebarVisible = false
        }) {
            Label("", systemImage: selected == timeline ? "\(img).fill" : img)
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, minHeight: 30.0)
        }
        .foregroundColor(selected != timeline ? .gray : .primary)
    }
}
    

struct TabBar: View {
    @Binding var new_events: NewEventsBits
    @Binding var selected: Timeline?
    @Binding var isSidebarVisible: Bool
    
    let action: (Timeline) -> ()
    
    var body: some View {
        VStack {
            Divider()
            HStack {
                TabButton(timeline: .home, img: "house", selected: $selected, new_events: $new_events, isSidebarVisible: $isSidebarVisible, action: action).keyboardShortcut("1")
                TabButton(timeline: .dms, img: "bubble.left.and.bubble.right", selected: $selected, new_events: $new_events, isSidebarVisible: $isSidebarVisible, action: action).keyboardShortcut("2")
                TabButton(timeline: .search, img: "magnifyingglass.circle", selected: $selected, new_events: $new_events, isSidebarVisible: $isSidebarVisible, action: action).keyboardShortcut("3")
                TabButton(timeline: .notifications, img: "bell", selected: $selected, new_events: $new_events, isSidebarVisible: $isSidebarVisible, action: action).keyboardShortcut("4")
            }
        }
    }
}
