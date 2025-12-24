//
//  NotificationSettings.swift
//  damus
//
//  Created by William Casarin on 2023-04-05.
//

import SwiftUI

let MINIMUM_PUSH_NOTIFICATION_SYNC_DELAY_IN_SECONDS = 0.25

struct NotificationSettingsView: View {
    let damus_state: DamusState
    @ObservedObject var settings: UserSettingsStore
    @State var notification_mode_setting_error: String? = nil
    @State var notification_preferences_sync_state: PreferencesSyncState = .undefined
    
    @Environment(\.dismiss) var dismiss

    func indicator_binding(_ val: NewEventsBits) -> Binding<Bool> {
        return Binding.init(get: {
            (settings.notification_indicators & val.rawValue) > 0
        }, set: { v in
            if v {
                settings.notification_indicators |= val.rawValue
            } else {
                settings.notification_indicators &= ~val.rawValue
            }
        })
    }

    var hellthread_notification_max_pubkeys_binding: Binding<Double> {
        Binding<Double>(get: {
            return Double(settings.hellthread_notification_max_pubkeys)
        }, set: {
            settings.hellthread_notification_max_pubkeys = Int($0)
        })
    }

    func try_to_set_notifications_mode(new_value: UserSettingsStore.NotificationsMode) {
        notification_mode_setting_error = nil
        if new_value == .push {
            Task {
                do {
                    try await damus_state.push_notification_client.send_token()
                    await self.sync_up_remote_notification_settings()
                    settings.notification_mode = new_value
                }
                catch {
                    notification_mode_setting_error = String(format: NSLocalizedString("Error configuring push notifications with the server: %@", comment: "Error label shown when user tries to enable push notifications but something fails"), error.localizedDescription)
                }
            }
        }
        else {
            Task {
                do {
                    try await damus_state.push_notification_client.revoke_token()
                    settings.notification_mode = new_value
                    notification_preferences_sync_state = .not_applicable
                }
                catch {
                    notification_mode_setting_error = String(format: NSLocalizedString("Error disabling push notifications with the server: %@", comment: "Error label shown when user tries to disable push notifications but something fails"), error.localizedDescription)
                }
            }
        }
    }
    
    // MARK: - Push notification preference sync management
    
    func notification_preference_binding<T>(_ raw_binding: Binding<T>) -> Binding<T> {
        return Binding(
            get: {
                return raw_binding.wrappedValue
            },
            set: { new_value in
                let old_value = raw_binding.wrappedValue
                raw_binding.wrappedValue = new_value
                if self.settings.notification_mode == .push {
                    Task {
                        await self.send_push_notification_preferences(on_failure: {
                            raw_binding.wrappedValue = old_value
                        })
                    }
                }
            }
        )
    }
    
    func sync_up_remote_notification_settings() async {
        do {
            notification_preferences_sync_state = .syncing
            let remote_settings = try await damus_state.push_notification_client.get_settings()
            let local_settings = PushNotificationClient.NotificationSettings.from(settings: settings)
            if remote_settings != local_settings {
                await self.send_push_notification_preferences(local_settings)
            }
            else {
                notification_preferences_sync_state = .success
            }
        }
        catch {
            notification_preferences_sync_state = .failure(error: String(format: NSLocalizedString("Failed to get push notification preferences from the server", comment: "Error label indicating about a failure in fetching notification preferences"), error.localizedDescription))
        }
    }
    
    func send_push_notification_preferences(_ new_settings: PushNotificationClient.NotificationSettings? = nil, on_failure: (() -> Void)? = nil) async {
        do {
            notification_preferences_sync_state = .syncing
            try await damus_state.push_notification_client.set_settings(new_settings)
            // Make sync appear to take at least a few milliseconds or so to avoid issues with labor perception bias (https://growth.design/case-studies/labor-perception-bias)
            DispatchQueue.main.asyncAfter(deadline: .now() + MINIMUM_PUSH_NOTIFICATION_SYNC_DELAY_IN_SECONDS) {
                notification_preferences_sync_state = .success
            }
        }
        catch {
            notification_preferences_sync_state = .failure(error: String(format: NSLocalizedString("Error syncing up push notifications preferences with the server: %@", comment: "Error label shown when system tries to sync up notification preferences to the push notification server but something fails"), error.localizedDescription))
            on_failure?()
        }
    }
    
    // MARK: - View layout

    func hellthread_notification_settings_text() -> String {
        if !settings.hellthread_notifications_disabled {
            return NSLocalizedString("Hide notifications that tag many profiles", comment: "Label for notification settings toggle that hides notifications that tag many people.")
        }
        return pluralizedString(key: "hellthread_notifications_disabled", count: $settings.hellthread_notification_max_pubkeys.wrappedValue)
    }

    var hellthread_notifications_max_pubkeys_view: some View {
        VStack(alignment: .leading) {
            Slider(
                value: self.notification_preference_binding(hellthread_notification_max_pubkeys_binding),
                in: Double(HELLTHREAD_MIN_PUBKEYS)...Double(HELLTHREAD_MAX_PUBKEYS),
                step: 1
            )
        }
    }

    var body: some View {
        Form {
            if settings.enable_push_notifications {
                Section(
                    header: Text("General", comment: "Section header for general damus notifications user configuration"),
                    footer: VStack {
                        if let notification_mode_setting_error {
                            Text(notification_mode_setting_error)
                                .foregroundStyle(.damusDangerPrimary)
                        }
                    }
                ) {
                    Picker(NSLocalizedString("Notifications mode", comment: "Prompt selection of the notification mode (Feature to switch between local notifications (generated from user's own phone) or push notifications (generated by Damus server)."),
                        selection: Binding(
                                get: { settings.notification_mode },
                                set: { newValue in
                                    self.try_to_set_notifications_mode(new_value: newValue)
                                }
                        )
                    ) {
                        ForEach(UserSettingsStore.NotificationsMode.allCases, id: \.self) { notification_mode in
                            Text(notification_mode.text_description())
                                .tag(notification_mode.rawValue)
                        }
                    }
                }
            }
            
            Section(
                header: Text("Notification Preferences", comment: "Section header for Notification Preferences"),
                footer: VStack(alignment: .leading, spacing: 8) {
                    switch notification_preferences_sync_state {
                        case .undefined, .not_applicable:
                            EmptyView()
                        case .success:
                            HStack {
                                Image("check-circle.fill")
                                    .foregroundStyle(.damusGreen)
                                Text("Successfully synced", comment: "Label indicating success in syncing notification preferences")
                            }
                        case .syncing:
                            HStack(spacing: 10) {
                                ProgressView()
                                Text("Syncing", comment: "Label indicating success in syncing notification preferences")
                            }
                        case .failure(let error):
                            Text(error)
                                .foregroundStyle(.damusDangerPrimary)
                    }

                    if AccountsStore.shared.accounts.count > 1 {
                        Text("Notifications are only delivered for your active account. Switch accounts to receive notifications for a different account.", comment: "Footer text explaining notifications only work for active account")
                            .padding(.top, 4)
                    }
                }
            ) {
                Toggle(NSLocalizedString("Zaps", comment: "Setting to enable Zap Local Notification"), isOn: self.notification_preference_binding($settings.zap_notification))
                    .toggleStyle(.switch)
                Toggle(NSLocalizedString("Mentions", comment: "Setting to enable Mention Local Notification"), isOn: self.notification_preference_binding($settings.mention_notification))
                    .toggleStyle(.switch)
                Toggle(NSLocalizedString("Reposts", comment: "Setting to enable Repost Local Notification"), isOn: self.notification_preference_binding($settings.repost_notification))
                    .toggleStyle(.switch)
                Toggle(NSLocalizedString("Likes", comment: "Setting to enable Like Local Notification"), isOn: self.notification_preference_binding($settings.like_notification))
                    .toggleStyle(.switch)
                Toggle(NSLocalizedString("DMs", comment: "Setting to enable DM Local Notification"), isOn: self.notification_preference_binding($settings.dm_notification))
                    .toggleStyle(.switch)
                Toggle(NSLocalizedString("Show only from users you follow", comment: "Setting to Show notifications only associated to users your follow"), isOn: self.notification_preference_binding($settings.notification_only_from_following))
                    .toggleStyle(.switch)
                VStack {
                    Toggle(hellthread_notification_settings_text(), isOn: self.notification_preference_binding($settings.hellthread_notifications_disabled))
                        .toggleStyle(.switch)
                    if settings.hellthread_notifications_disabled {
                        hellthread_notifications_max_pubkeys_view
                    }
                }
            }
            
            Section(
                header: Text("Notification Dots", comment: "Section header for notification indicator dot settings"),
                footer: Text("").padding(.bottom, tabHeight + getSafeAreaBottom())
            ) {
                Toggle(NSLocalizedString("Zaps", comment: "Setting to enable Zap Local Notification"), isOn: indicator_binding(.zaps))
                    .toggleStyle(.switch)
                Toggle(NSLocalizedString("Mentions", comment: "Setting to enable Mention Local Notification"), isOn: indicator_binding(.mentions))
                    .toggleStyle(.switch)
                Toggle(NSLocalizedString("Reposts", comment: "Setting to enable Repost Local Notification"), isOn: indicator_binding(.reposts))
                    .toggleStyle(.switch)
                Toggle(NSLocalizedString("Likes", comment: "Setting to enable Like Local Notification"), isOn: indicator_binding(.likes))
                    .toggleStyle(.switch)
            }
        }
        .navigationTitle("Notifications")
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
        }
        .onAppear(perform: {
            Task {
                if self.settings.notification_mode == .push {
                    await self.sync_up_remote_notification_settings()
                }
            }
        })
    }
}

extension NotificationSettingsView {
    enum PreferencesSyncState {
        /// State is unknown
        case undefined
        /// State is not applicable (e.g. Notifications are set to local)
        case not_applicable
        /// Preferences are successfully synced
        case success
        /// Preferences are being synced
        case syncing
        /// There was a failure during syncing
        case failure(error: String)
    }
}


struct NotificationSettings_Previews: PreviewProvider {
    static var previews: some View {
        NotificationSettingsView(damus_state: test_damus_state, settings: UserSettingsStore())
    }
}
