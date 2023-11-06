//
//  DeveloperSettingsView.swift
//  damus
//
//  Created by Bryan Montz on 7/6/23.
//

import Foundation
import SwiftUI

struct DeveloperSettingsView: View {
    @ObservedObject var settings: UserSettingsStore
    
    var body: some View {
        Form {
            Section(footer: Text(NSLocalizedString("Developer Mode enables features and options that may help developers diagnose issues and improve this app. Most users will not need Developer Mode.", comment: "Section header for Developer Settings view"))) {
                Toggle(NSLocalizedString("Developer Mode", comment: "Setting to enable developer mode"), isOn: $settings.developer_mode)
                    .toggleStyle(.switch)
                if settings.developer_mode {
                    Toggle(NSLocalizedString("Always show onboarding", comment: "Setting to always show onboarding suggestions, for developers who need to test onboarding"), isOn: $settings.always_show_onboarding_suggestions)
                        .toggleStyle(.switch)
                }
            }
        }
        .navigationTitle(NSLocalizedString("Developer", comment: "Navigation title for developer settings"))
    }
}
