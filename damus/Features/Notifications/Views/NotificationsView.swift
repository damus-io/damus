//
//  NotificationsView.swift
//  damus
//
//  Created by William Casarin on 2023-02-21.
//

import SwiftUI
import TipKit

class NotificationFilter: ObservableObject, Equatable {
    @Published var state: NotificationFilterState
    @Published var friend_filter: FriendFilter
    @Published var hellthread_notifications_disabled: Bool
    @Published var hellthread_notification_max_pubkeys: Int

    static func == (lhs: NotificationFilter, rhs: NotificationFilter) -> Bool {
        return lhs.state == rhs.state
            && lhs.friend_filter == rhs.friend_filter
            && lhs.hellthread_notifications_disabled == rhs.hellthread_notifications_disabled
            && lhs.hellthread_notification_max_pubkeys == rhs.hellthread_notification_max_pubkeys
    }
    
    init(
        state: NotificationFilterState = .all,
        friend_filter: FriendFilter = .all,
        hellthread_notifications_disabled: Bool = false,
        hellthread_notification_max_pubkeys: Int = DEFAULT_HELLTHREAD_MAX_PUBKEYS
    ) {
        self.state = state
        self.friend_filter = friend_filter
        self.hellthread_notifications_disabled = hellthread_notifications_disabled
        self.hellthread_notification_max_pubkeys = hellthread_notification_max_pubkeys
    }
    
    func filter(contacts: Contacts, mutelist_manager: MutelistManager, items: [NotificationItem]) -> [NotificationItem] {
        
        return items.reduce(into: []) { acc, item in
            if !self.state.filter(item) {
                return
            }

            if let item = item.filter({ ev in
                !mutelist_manager.is_event_muted(ev) &&
                self.friend_filter.filter(contacts: contacts, pubkey: ev.pubkey) &&
                (!hellthread_notifications_disabled || !ev.is_hellthread(max_pubkeys: hellthread_notification_max_pubkeys)) &&
                // Allow notes that are created no more than 3 seconds in the future
                // to account for natural clock skew between sender and receiver.
                ev.age >= -3
            }) {
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
        let showTrustedButton = would_filter_non_friends_from_notifications(contacts: state.contacts, state: filter_state, items: self.notifications.notifications)
        TabView(selection: $filter_state) {
            NotificationTab(
                NotificationFilter(
                    state: .all,
                    friend_filter: filter.friend_filter,
                    hellthread_notifications_disabled: state.settings.hellthread_notifications_disabled,
                    hellthread_notification_max_pubkeys: state.settings.hellthread_notification_max_pubkeys
                )
            )
            .tag(NotificationFilterState.all)
            
            NotificationTab(
                NotificationFilter(
                    state: .zaps,
                    friend_filter: filter.friend_filter,
                    hellthread_notifications_disabled: state.settings.hellthread_notifications_disabled,
                    hellthread_notification_max_pubkeys: state.settings.hellthread_notification_max_pubkeys
                )
            )
            .tag(NotificationFilterState.zaps)
            
            NotificationTab(
                NotificationFilter(
                    state: .replies,
                    friend_filter: filter.friend_filter,
                    hellthread_notifications_disabled: state.settings.hellthread_notifications_disabled,
                    hellthread_notification_max_pubkeys: state.settings.hellthread_notification_max_pubkeys
                )
            )
            .tag(NotificationFilterState.replies)
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(
                    action: { state.nav.push(route: Route.NotificationSettings(settings: state.settings)) },
                    label: {
                        Image(systemName: "gearshape")
                            .frame(width: 24, height: 24)
                            .foregroundColor(.gray)
                    }
                )
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                if showTrustedButton {
                    TrustedNetworkButton(filter: $filter.friend_filter) {
                        if #available(iOS 17, *) {
                            TrustedNetworkButtonTip.shared.invalidate(reason: .actionPerformed)
                        }
                    }
                }
            }
        }
        .onChange(of: filter.friend_filter) { val in
            state.settings.friend_filter = val
            self.subtitle = filter.friend_filter.description()
        }
        .onChange(of: filter_state) { val in
            filter.state = val
        }
        .onAppear {
            self.filter.friend_filter = state.settings.friend_filter
            self.subtitle = filter.friend_filter.description()
            filter.state = filter_state
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if #available(iOS 17, *), showTrustedButton {
                    TipView(TrustedNetworkButtonTip.shared)
                        .tipBackground(.clear)
                        .tipViewStyle(TrustedNetworkButtonTipViewStyle())
                        .padding(.horizontal)
                }

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
                let notifs = Array(zip(1..., filter.filter(contacts: state.contacts, mutelist_manager: state.mutelist_manager, items: notifications.notifications)))
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

