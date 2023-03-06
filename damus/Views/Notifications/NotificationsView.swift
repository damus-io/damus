//
//  NotificationsView.swift
//  damus
//
//  Created by William Casarin on 2023-02-21.
//

import SwiftUI

enum NotificationFilterState {
    case all
    case zaps
    case replies
    
    func filter(_ item: NotificationItem) -> Bool {
        switch self {
        case .all:
            return true
        case .replies:
            return item.is_reply != nil
        case .zaps:
            return item.is_zap != nil
        }
    }
}

struct NotificationsView: View {
    let state: DamusState
    @ObservedObject var notifications: NotificationsModel
    @State var filter_state: NotificationFilterState = .all
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        TabView(selection: $filter_state) {
            NotificationTab(NotificationFilterState.all)
                .tag(NotificationFilterState.all)
                .id(NotificationFilterState.all)
            
            NotificationTab(NotificationFilterState.zaps)
                .tag(NotificationFilterState.zaps)
                .id(NotificationFilterState.zaps)
            
            NotificationTab(NotificationFilterState.replies)
                .tag(NotificationFilterState.replies)
                .id(NotificationFilterState.replies)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                CustomPicker(selection: $filter_state, content: {
                    Text("All", comment: "Label for filter for all notifications.")
                        .tag(NotificationFilterState.all)
                    
                    Text("Zaps", comment: "Label for filter for zap notifications.")
                        .tag(NotificationFilterState.zaps)
                    
                    Text("Mentions", comment: "Label for filter for seeing mention notifications (replies, etc).")
                        .tag(NotificationFilterState.replies)
                    
                })
                Divider()
                    .frame(height: 1)
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
        }
    }
    
    func NotificationTab(_ filter: NotificationFilterState) -> some View {
        ScrollViewReader { scroller in
            ScrollView {
                LazyVStack(alignment: .leading) {
                    Color.white.opacity(0)
                        .id("startblock")
                        .frame(height: 5)
                    ForEach(notifications.notifications.filter(filter.filter), id: \.id) { item in
                        NotificationItemView(state: state, item: item)
                    }
                }
                .background(GeometryReader { proxy -> Color in
                    DispatchQueue.main.async {
                        handle_scroll_queue(proxy, queue: self.notifications)
                    }
                    return Color.clear
                })
                .padding(.horizontal)
            }
            .coordinateSpace(name: "scroll")
            .onReceive(handle_notify(.scroll_to_top)) { notif in
                let _ = notifications.flush()
                self.notifications.should_queue = false
                scroll_to_event(scroller: scroller, id: "startblock", delay: 0.0, animate: true, anchor: .top)
            }
        }
        .onAppear {
            let _ = notifications.flush()
        }
    }
}

struct NotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationsView(state: test_damus_state(), notifications: NotificationsModel(), filter_state: .all )
    }
}
