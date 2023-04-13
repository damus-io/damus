//
//  NotificationsView.swift
//  damus
//
//  Created by William Casarin on 2023-02-21.
//

import SwiftUI

enum NotificationFilterState: String {
    case all
    case zaps
    case replies
    
    func is_other( item: NotificationItem) -> Bool {
        return item.is_zap == nil && item.is_reply == nil
    }
    
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
    
    var mystery: some View {
        VStack(spacing: 20) {
            Text("Wake up \(Profile.displayName(profile: state.profiles.lookup(id: state.pubkey), pubkey: state.pubkey).display_name)")
            Text("You are dreaming...")
        }
        .id("what")
    }
    
    var body: some View {
        TabView(selection: $filter_state) {
            mystery
            
            // This is needed or else there is a bug when switching from the 3rd or 2nd tab to first. no idea why.
            NotificationTab(NotificationFilterState.all)
                .tag(NotificationFilterState.all)
            
            NotificationTab(NotificationFilterState.zaps)
                .tag(NotificationFilterState.zaps)
            
            NotificationTab(NotificationFilterState.replies)
                .tag(NotificationFilterState.replies)
        }
        .onChange(of: filter_state) { val in
            save_notification_filter_state(pubkey: state.pubkey, state: val)
        }
        .onAppear {
            self.filter_state = load_notification_filter_state(pubkey: state.pubkey)
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
        NotificationsView(state: test_damus_state(), notifications: NotificationsModel(), filter_state: NotificationFilterState.all)
    }
}

func notification_filter_state_key(pubkey: String) -> String {
    return pk_setting_key(pubkey, key: "notification_filter_state")
}

func load_notification_filter_state(pubkey: String) -> NotificationFilterState {
    let key = notification_filter_state_key(pubkey: pubkey)
    
    guard let state_str = UserDefaults.standard.string(forKey: key) else {
        return .all
    }
    
    guard let state = NotificationFilterState(rawValue: state_str) else {
        return .all
    }
    
    return state
}


func save_notification_filter_state(pubkey: String, state: NotificationFilterState)  {
    let key = notification_filter_state_key(pubkey: pubkey)
    UserDefaults.standard.set(state.rawValue, forKey: key)
}
