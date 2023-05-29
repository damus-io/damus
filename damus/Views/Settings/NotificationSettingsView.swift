//
//  NotificationSettings.swift
//  damus
//
//  Created by William Casarin on 2023-04-05.
//

import SwiftUI

struct NotificationSettingsView: View {
    @ObservedObject var settings: UserSettingsStore
    
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
    
    var body: some View {
        Form {
            Section(header: Text(NSLocalizedString("Local Notifications", comment: "Section header for damus local notifications user configuration"))) {
                Toggle(NSLocalizedString("Zaps", comment: "Setting to enable Zap Local Notification"), isOn: $settings.zap_notification)
                    .toggleStyle(.switch)
                Toggle(NSLocalizedString("Mentions", comment: "Setting to enable Mention Local Notification"), isOn: $settings.mention_notification)
                    .toggleStyle(.switch)
                Toggle(NSLocalizedString("Reposts", comment: "Setting to enable Repost Local Notification"), isOn: $settings.repost_notification)
                    .toggleStyle(.switch)
                Toggle(NSLocalizedString("Likes", comment: "Setting to enable Like Local Notification"), isOn: $settings.like_notification)
                    .toggleStyle(.switch)
                Toggle(NSLocalizedString("DMs", comment: "Setting to enable DM Local Notification"), isOn: $settings.dm_notification)
                    .toggleStyle(.switch)
            }

            Section(header: Text(NSLocalizedString("Notification Preference", comment: "Section header for Notification Preferences"))) {
                Toggle(NSLocalizedString("Show only from users you follow", comment: "Setting to Show notifications only associated to users your follow"), isOn: $settings.notification_only_from_following)
                    .toggleStyle(.switch)
            }
            
            Section(header: Text(NSLocalizedString("Notification Dots", comment: "Section header for notification indicator dot settings"))) {
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
    }
}


struct NotificationSettings_Previews: PreviewProvider {
    static var previews: some View {
        NotificationSettingsView(settings: UserSettingsStore())
    }
}
