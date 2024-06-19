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
            Section(footer: Text("Developer Mode enables features and options that may help developers diagnose issues and improve this app. Most users will not need Developer Mode.", comment: "Section header for Developer Settings view")) {
                Toggle(NSLocalizedString("Developer Mode", comment: "Setting to enable developer mode"), isOn: $settings.developer_mode)
                    .toggleStyle(.switch)
                if settings.developer_mode {
                    Toggle(NSLocalizedString("Always show onboarding", comment: "Developer mode setting to always show onboarding suggestions."), isOn: $settings.always_show_onboarding_suggestions)

                    Toggle(NSLocalizedString("Enable experimental push notifications", comment: "Developer mode setting to enable experimental push notifications."), isOn: $settings.enable_experimental_push_notifications)
                        .toggleStyle(.switch)

                    Toggle(NSLocalizedString("Send device token to localhost", comment: "Developer mode setting to send device token metadata to a local server instead of the damus.io server."), isOn: $settings.send_device_token_to_localhost)
                        .toggleStyle(.switch)
                    
                    Toggle(NSLocalizedString("Enable experimental Purple API support", comment: "Developer mode setting to enable experimental Purple API support."), isOn: $settings.enable_experimental_purple_api)
                        .toggleStyle(.switch)
                    
                    Picker(NSLocalizedString("Damus Purple environment", comment: "Prompt selection of the Damus purple environment (Developer feature to switch between real/production mode to test modes)."), 
                           selection: Binding(
                            get: { () -> DamusPurpleEnvironment in
                                switch settings.purple_enviroment {
                                    case .local_test(_):
                                        return .local_test(host: nil)    // Avoid errors related to a value which is not a valid picker option
                                    default:
                                        return settings.purple_enviroment
                                }
                            },
                            set: { new_value in
                                settings.purple_enviroment = new_value
                            }
                           )
                    ) {
                        ForEach(DamusPurpleEnvironment.allCases, id: \.self) { purple_environment in
                            Text(purple_environment.text_description())
                                .tag(purple_environment.to_string())
                        }
                    }
                    
                    if case .local_test(_) = settings.purple_enviroment {
                        TextField(
                            NSLocalizedString("URL", comment: "Custom URL host for Damus Purple testing"),
                            text: Binding.init(
                                get: {
                                    return settings.purple_enviroment.custom_host() ?? ""
                                }, set: { new_host_value in
                                    settings.purple_enviroment = .local_test(host: new_host_value)
                                }
                            )
                        )
                            .disableAutocorrection(true)
                            .autocapitalization(UITextAutocapitalizationType.none)
                    }

                    Toggle(NSLocalizedString("Enable experimental Purple In-app purchase support", comment: "Developer mode setting to enable experimental Purple In-app purchase support."), isOn: $settings.enable_experimental_purple_iap_support)
                        .toggleStyle(.switch)
                }
            }
        }
        .navigationTitle(NSLocalizedString("Developer", comment: "Navigation title for developer settings"))
    }
}
