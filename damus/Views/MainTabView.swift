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
    
    var description: String {
        return self.rawValue
    }
}


struct MainTabView: View {
    var body: some View {
        Text(/*@START_MENU_TOKEN@*/"Hello, World!"/*@END_MENU_TOKEN@*/)
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}

struct NotificationsTab: View {
    @Binding var new_notifications: Bool
    @Binding var selected: Timeline?
    
    let action: (Timeline) -> ()
    
    var body: some View {
        ZStack(alignment: .center) {
            TabButton(timeline: .notifications, img: "bell", selected: $selected, action: action)
            
            if new_notifications {
                Circle()
                    .size(CGSize(width: 8, height: 8))
                    .frame(width: 10, height: 10, alignment: .topTrailing)
                    .alignmentGuide(VerticalAlignment.center) { a in a.height + 2.0 }
                    .alignmentGuide(HorizontalAlignment.center) { a in a.width - 12.0 }
                    .foregroundColor(.accentColor)
            }
        }
    }
}

    
struct TabButton: View {
    let timeline: Timeline
    let img: String
    
    @Binding var selected: Timeline?
    
    let action: (Timeline) -> ()
    
    var body: some View {
        Button(action: {action(timeline)}) {
            Label("", systemImage: selected == timeline ? "\(img).fill" : img)
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity, minHeight: 30.0)
        }
        .foregroundColor(selected != timeline ? .gray : .primary)
    }
}
    

struct TabBar: View {
    @Binding var new_notifications: Bool
    @Binding var selected: Timeline?
    
    let action: (Timeline) -> ()
    
    var body: some View {
        VStack {
            Divider()
            HStack {
                TabButton(timeline: .home, img: "house", selected: $selected, action: action)
                TabButton(timeline: .search, img: "magnifyingglass.circle", selected: $selected, action: action)
                NotificationsTab(new_notifications: $new_notifications, selected: $selected, action: action)
            }
        }
    }
}

