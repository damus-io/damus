//
//  NotificationsView.swift
//  damus
//
//  Created by William Casarin on 2023-02-21.
//

import SwiftUI

class NotificationFilter: ObservableObject, Equatable {
    @Published var state: NotificationFilterState
    @Published var fine_filter: FriendFilter
    
    static func == (lhs: NotificationFilter, rhs: NotificationFilter) -> Bool {
        return lhs.state == rhs.state && lhs.fine_filter == rhs.fine_filter
    }
    
    init(state: NotificationFilterState = .all, fine_filter: FriendFilter = .all) {
        self.state = state
        self.fine_filter = fine_filter
    }
    
    func filter(contacts: Contacts, items: [NotificationItem]) -> [NotificationItem] {
        
        return items.reduce(into: []) { acc, item in
            if !self.state.filter(item) {
                return
            }
            
            if let item = item.filter({ self.fine_filter.filter(contacts: contacts, pubkey: $0.pubkey) }) {
                acc.append(item)
            }
        }
    }
}

enum NotificationFilterState: String {
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
    @StateObject var filter = NotificationFilter()
    @SceneStorage("NotificationsView.filter_state") var filter_state: NotificationFilterState = .all
    @Binding var subtitle: String?
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        TabView(selection: $filter_state) {
            NotificationTab(
                NotificationFilter(
                    state: .all,
                    fine_filter: filter.fine_filter
                )
            )
            .tag(NotificationFilterState.all)
            
            NotificationTab(
                NotificationFilter(
                    state: .zaps,
                    fine_filter: filter.fine_filter
                )
            )
            .tag(NotificationFilterState.zaps)
            
            NotificationTab(
                NotificationFilter(
                    state: .replies,
                    fine_filter: filter.fine_filter
                )
            )
            .tag(NotificationFilterState.replies)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(
                    action: { state.nav.push(route: Route.NotificationSettings(settings: state.settings)) },
                    label: {
                        Image("settings")
                            .foregroundColor(.gray)
                    }
                )
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if would_filter_non_friends_from_notifications(contacts: state.contacts, state: filter_state, items: self.notifications.notifications) {
                    FriendsButton(filter: $filter.fine_filter)
                }
            }
        }
        .onChange(of: filter.fine_filter) { val in
            state.settings.friend_filter = val
            self.subtitle = filter.fine_filter.description()
        }
        .onChange(of: filter_state) { val in
            filter.state = val
        }
        .onAppear {
            self.filter.fine_filter = state.settings.friend_filter
            self.subtitle = filter.fine_filter.description()
            filter.state = filter_state
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                CustomPicker(tabs: [
                    (NSLocalizedString("All", comment: "Label for filter for all notifications."), NotificationFilterState.all),
                    (NSLocalizedString("Zaps", comment: "Label for filter for zap notifications."), NotificationFilterState.zaps),
                    (NSLocalizedString("Mentions", comment: "Label for filter for seeing mention notifications (replies, etc)."), NotificationFilterState.replies),
                ], selection: $filter_state)
                Divider()
                    .frame(height: 1)
            }
            .background(colorScheme == .dark ? Color.black : Color.white)
        }
    }
    
    func NotificationTab(_ filter: NotificationFilter) -> some View {
        ScrollViewReader { scroller in
            ScrollView {
                let notifs = Array(zip(1..., filter.filter(contacts: state.contacts, items: notifications.notifications)))
                if notifs.isEmpty {
                    EmptyTimelineView()
                } else {
                    LazyVStack(alignment: .leading) {
                        Color.white.opacity(0)
                            .id("startblock")
                            .frame(height: 5)
                        ForEach(notifs, id: \.0) { zip in
                            NotificationItemView(state: state, item: zip.1)
                        }
                    }
                    .background(GeometryReader { proxy -> Color in
                        DispatchQueue.main.async {
                            handle_scroll_queue(proxy, queue: self.notifications)
                        }
                        return Color.clear
                    })
                }
            }
            .coordinateSpace(name: "scroll")
            .onReceive(handle_notify(.scroll_to_top)) { notif in
                let _ = notifications.flush(state)
                self.notifications.should_queue = false
                scroll_to_event(scroller: scroller, id: "startblock", delay: 0.0, animate: true, anchor: .top)
            }
        }
        .onAppear {
            let _ = notifications.flush(state)
        }
    }
}

struct NotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationsView(state: test_damus_state, notifications: NotificationsModel(), filter: NotificationFilter(), subtitle: .constant(nil))
    }
}

func would_filter_non_friends_from_notifications(contacts: Contacts, state: NotificationFilterState, items: [NotificationItem]) -> Bool {
    for item in items {
        // this is only valid depending on which tab we're looking at
        if !state.filter(item) {
            continue
        }
        
        if item.would_filter({ ev in FriendFilter.friends_of_friends.filter(contacts: contacts, pubkey: ev.pubkey) }) {
            return true
        }
    }
    
    return false
}

