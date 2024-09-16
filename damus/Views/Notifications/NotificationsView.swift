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
    @State var show_push_notification_friends_only_setting_confirmation_dialog: Bool = false
    @State var push_notification_settings_syncing_error_occurred: Bool = false
    
    @Environment(\.colorScheme) var colorScheme
    
    var mystery: some View {
        let profile_txn = state.profiles.lookup(id: state.pubkey)
        let profile = profile_txn?.unsafeUnownedValue
        return VStack(spacing: 20) {
            Text("Wake up, \(Profile.displayName(profile: profile, pubkey: state.pubkey).displayName.truncate(maxLength: 50))", comment: "Text telling the user to wake up, where the argument is their display name.")
            Text("You are dreaming...", comment: "Text telling the user that they are dreaming.")
        }
        .id("what")
    }
    
    var body: some View {
        TabView(selection: $filter_state) {
            // This is needed or else there is a bug when switching from the 3rd or 2nd tab to first. no idea why.
            mystery
            
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
                if would_filter_non_friends_from_notifications(contacts: state.contacts, state: filter_state, items: self.notifications.notifications) {
                    FriendsButton(filter: $filter.fine_filter)
                }
            }
        }
        .onChange(of: filter.fine_filter) { val in
            state.settings.friend_filter = val
            self.suggest_matching_notification_settings_to_friends_filter_if_needed(friends_filter: val)
        }
        .confirmationDialog(
            NSLocalizedString("Would you like to also update your iOS notification preferences to match this view filter?", comment: "Confirmation dialog that shows when switching friends filter on/off on the notifications view"),
            isPresented: $show_push_notification_friends_only_setting_confirmation_dialog,
            titleVisibility: .visible
        ) {
            Button(NSLocalizedString("Yes", comment: "Button label to confirm intent to update iOS notification settings to match the friends filter")) {
                self.update_notification_settings_to_match(state.settings.friend_filter)
                show_push_notification_friends_only_setting_confirmation_dialog = false
            }
            Button(NSLocalizedString("Not now", comment: "Button label to reject updating iOS notification settings to match the friends filter")) {
                show_push_notification_friends_only_setting_confirmation_dialog = false
            }.keyboardShortcut(.defaultAction)
            Button(NSLocalizedString("Never, don’t ask me again", comment: "Button label to permanently reject updating iOS notification settings to match the friends filter"), role: .destructive) {
                state.settings.never_show_match_friends_filter_with_notification_only_from_following_suggestion = true
                show_push_notification_friends_only_setting_confirmation_dialog = false
            }
        }
        .alert(
            NSLocalizedString("Error syncing push notification settings", comment: "Error alert message"),
            isPresented: $push_notification_settings_syncing_error_occurred,
            actions: {
                Button(NSLocalizedString("Dismiss", comment: "Button to dismiss error")) {
                    push_notification_settings_syncing_error_occurred = false
                }
                
                Button(NSLocalizedString("Go to notification settings", comment: "Button to go to the notification settings presented after being alerted of an error")) {
                    push_notification_settings_syncing_error_occurred = false
                    state.nav.push(route: Route.NotificationSettings(settings: state.settings))
                }
            },
            message: {
                Text(
                    "Sorry, something went wrong when updating your push notification settings with our servers. Please go to Notification settings to try updating the settings manually, or contact Damus support if that fails.",
                    comment: "Error message when syncing push notifications, with actionable advice for the user."
                )
            }
        )
        .onChange(of: filter_state) { val in
            filter.state = val
        }
        .onAppear {
            self.filter.fine_filter = state.settings.friend_filter
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
                LazyVStack(alignment: .leading) {
                    Color.white.opacity(0)
                        .id("startblock")
                        .frame(height: 5)
                    let notifs = Array(zip(1..., filter.filter(contacts: state.contacts, items: notifications.notifications)))
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
    
    // MARK: Functions to help syncing notification settings to match the friend filter
    
    /// Check if we should ask the user if they want to update notification settings
    func suggest_matching_notification_settings_to_friends_filter_if_needed(friends_filter: FriendFilter) {
        if state.settings.notification_only_from_following != self.corresponding_notification_only_from_following_setting(from: friends_filter)
           && state.settings.never_show_match_friends_filter_with_notification_only_from_following_suggestion == false {
            // "only get notification from following" setting does not match this filter. Offer user to change that config as well.
            self.show_push_notification_friends_only_setting_confirmation_dialog = true
        }
    }
    
    /// Converts a friend filter setting to the matching "notification only from following" setting
    func corresponding_notification_only_from_following_setting(from friend_filter: FriendFilter) -> Bool {
        return (friend_filter == .friends)
    }
    
    func update_notification_settings_to_match(_ friend_filter: FriendFilter) {
        Task {
            let original_setting = state.settings.notification_only_from_following
            state.settings.notification_only_from_following = self.corresponding_notification_only_from_following_setting(from: state.settings.friend_filter)
            if state.settings.notification_mode == .push {
                let local_settings = PushNotificationClient.NotificationSettings.from(settings: state.settings)
                do {
                    try await state.push_notification_client.set_settings(local_settings)
                }
                catch {
                    // Something went wrong. Revert setting back to the original
                    state.settings.notification_only_from_following = original_setting
                    // Notify user of what happened and provide advice
                    push_notification_settings_syncing_error_occurred = true
                }
            }
        }
    }
}

struct NotificationsView_Previews: PreviewProvider {
    static var previews: some View {
        NotificationsView(state: test_damus_state, notifications: NotificationsModel(), filter: NotificationFilter())
    }
}

func would_filter_non_friends_from_notifications(contacts: Contacts, state: NotificationFilterState, items: [NotificationItem]) -> Bool {
    for item in items {
        // this is only valid depending on which tab we're looking at
        if !state.filter(item) {
            continue
        }
        
        if item.would_filter({ ev in FriendFilter.friends.filter(contacts: contacts, pubkey: ev.pubkey) }) {
            return true
        }
    }
    
    return false
}
