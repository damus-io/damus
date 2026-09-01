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
    
    @MainActor
    func filter(contacts: Contacts, items: [NotificationItem]) -> [NotificationItem] {
        
        return items.reduce(into: []) { acc, item in
            if !self.state.filter(item) {
                return
            }

            if let item = item.filter({ ev in
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

extension NotificationFilterState {
    /// The labelled options the notifications filter selector offers.
    ///
    /// Shared by the top ``CustomPicker`` and the tab view's bottom accessory —
    /// only one of the two is on screen at a time, but they must offer the same
    /// options in the same order, so the labels live in one place.
    static var timeline_filter_options: [(String, NotificationFilterState)] {
        [
            (NSLocalizedString("All", comment: "Label for filter for all notifications."), .all),
            (NSLocalizedString("Zaps", comment: "Label for filter for zap notifications."), .zaps),
            (NSLocalizedString("Mentions", comment: "Label for filter for seeing mention notifications (replies, etc)."), .replies),
        ]
    }
}

struct NotificationsView: View {
    let state: DamusState
    @ObservedObject var notifications: NotificationsModel
    @StateObject var filter = NotificationFilter()
    /// Which notifications to show.
    ///
    /// Owned by ``ContentView`` rather than by this view, because on iOS 26 the
    /// selector for it is the tab view's bottom accessory, which attaches to the
    /// `TabView` and so cannot reach state that lives in here.
    @Binding var filter_state: NotificationFilterState
    @Binding var subtitle: String?

    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        let showTrustedButton = would_filter_non_friends_from_notifications(contacts: state.contacts, state: filter_state, items: self.notifications.notifications)
        // Driven by the filter selector: the `CustomPicker` below pre-26, the
        // tab view's bottom glass accessory from iOS 26 on. This used to be a
        // `TabView` with no explicit style, which meant it defaulted to the
        // *bar* style and drew a second, unlabelled tab bar of its own —
        // harmless while the old custom `TabBar` overlay covered that strip, and
        // plainly visible once the tab bar became native glass. It is also, as
        // it happens, where the bottom accessory idea came from. Rendering the
        // selected filter directly removes that phantom bar and hands the real
        // `ScrollView` to the tab bar, so it can still minimize on scroll.
        // Switching to a paged `TabView` would have removed the phantom bar too,
        // but at the cost of the minimize behaviour and an opaque slab behind
        // the glass. The cost here is the swipe-between-filters gesture, which
        // the selector already duplicates.
        NotificationTab(
            NotificationFilter(
                state: filter_state,
                friend_filter: filter.friend_filter,
                hellthread_notifications_disabled: state.settings.hellthread_notifications_disabled,
                hellthread_notification_max_pubkeys: state.settings.hellthread_notification_max_pubkeys
            )
        )
        .id(filter_state)
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
            .hideToolbarBackground()
            
            ToolbarItem(placement: .navigationBarTrailing) {
                if showTrustedButton {
                    TrustedNetworkButton(filter: $filter.friend_filter) {
                        if #available(iOS 17, *) {
                            TrustedNetworkButtonTip.shared.invalidate(reason: .actionPerformed)
                        }
                    }
                }
            }
            .hideToolbarBackground()
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

                if !timelineFilterLivesInTabViewAccessory {
                    CustomPicker(tabs: NotificationFilterState.timeline_filter_options, selection: $filter_state)
                    Divider()
                        .frame(height: 1)
                }
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

            // Disable queuing once the tab is visible. This ensures any events
            // arriving after onAppear insert immediately rather than being queued
            // indefinitely. Acts as a safety net alongside the ndbEose flush in
            // HomeModel - whichever fires first will disable queuing.
            notifications.set_should_queue(false)
        }
    }
}

struct NotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationsView(state: test_damus_state, notifications: NotificationsModel(), filter: NotificationFilter(), filter_state: .constant(.all), subtitle: .constant(nil))
    }
}

@MainActor
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

