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
    let damus_state: DamusState
    
    var body: some View {
        Form {
            Section(footer: Text("Developer Mode enables features and options that may help developers diagnose issues and improve this app. Most users will not need Developer Mode.", comment: "Section header for Developer Settings view")) {
                Toggle(NSLocalizedString("Developer Mode", comment: "Setting to enable developer mode"), isOn: $settings.developer_mode)
                    .toggleStyle(.switch)
                if settings.developer_mode {
                    Toggle(NSLocalizedString("Undistract mode", comment: "Developer mode setting to scramble text and images to avoid distractions during development."), isOn: $settings.undistractMode)
                    Toggle(NSLocalizedString("Always show onboarding", comment: "Developer mode setting to always show onboarding suggestions."), isOn: $settings.always_show_onboarding_suggestions)
                    Picker(NSLocalizedString("Push notification environment", comment: "Prompt selection of the Push notification environment (Developer feature to switch between real/production mode to test modes)."),
                           selection: Binding(
                            get: { () -> PushNotificationClient.Environment in
                                switch settings.push_notification_environment {
                                    case .local_test(_):
                                        return .local_test(host: nil)    // Avoid errors related to a value which is not a valid picker option
                                    default:
                                        return settings.push_notification_environment
                                }
                            },
                            set: { new_value in
                                settings.push_notification_environment = new_value
                            }
                           )
                    ) {
                        ForEach(PushNotificationClient.Environment.allCases, id: \.self) { push_notification_environment in
                            Text(push_notification_environment.text_description())
                                .tag(push_notification_environment.to_string())
                        }
                    }
                    
                    if case .local_test(_) = settings.push_notification_environment {
                        TextField(
                            NSLocalizedString("URL", comment: "Custom URL host for Damus push notification testing"),
                            text: Binding.init(
                                get: {
                                    return settings.push_notification_environment.custom_host() ?? ""
                                }, set: { new_host_value in
                                    settings.push_notification_environment = .local_test(host: new_host_value)
                                }
                            )
                        )
                            .disableAutocorrection(true)
                            .autocapitalization(UITextAutocapitalizationType.none)
                    }
                    
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

                    if #available(iOS 17, *) {
                        Toggle(NSLocalizedString("Reset tips on launch", comment: "Developer mode setting to reset tips upon app first launch. Tips are visual contextual hints that highlight new, interesting, or unused features users have not discovered yet."), isOn: $settings.reset_tips_on_launch)
                            .toggleStyle(.switch)
                    }
                    
                    SnapshotNdbButton(damus_state: self.damus_state)
                }
            }
        }
        .navigationTitle(NSLocalizedString("Developer", comment: "Navigation title for developer settings"))
    }
}

extension DeveloperSettingsView {
    struct SnapshotNdbButton: View {
        let damus_state: DamusState
        @State var snapshotState: SnapshotState = .notDone
        @State var snapshotTask: Task<Void, Never>? = nil
        
        var body: some View {
            Button(action: { self.snapshot() }, label: {
                HStack(spacing: 6) {
                    switch snapshotState {
                    case .notDone:
                        Text("Snapshot Ndb to shared container", comment: "Developer settings button to snapshot ndb to shared container.")
                    case .inProgress:
                        ProgressView()
                        Text("Snapshotting Ndb to shared container", comment: "Developer settings loading message indicating that ndb is being snapshotted to the shared container.")
                    case .done:
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("Ndb has been snapshotted successfully", comment: "Developer settings message indicating that ndb was successfully snapshotted.")
                    case .error(let errorMessage):
                        Image(systemName: "xmark.circle")
                            .foregroundColor(.red)
                        Text(errorMessage)
                    }
                }
            })
            .disabled(self.snapshotState.isInProgress())
        }
        
        func snapshot() {
            Task {
                snapshotTask?.cancel()
                await snapshotTask?.value
                snapshotTask = Task {
                    self.snapshotState = .inProgress
                    do {
                        try await damus_state.snapshotManager.performSnapshot()
                        self.snapshotState = .done
                    } catch {
                        self.snapshotState = .error(error.localizedDescription)
                    }
                }
            }
        }
        
        enum SnapshotState {
            case notDone
            case inProgress
            case done
            case error(String)
            
            func isInProgress() -> Bool {
                if case .inProgress = self {
                    return true
                }
                else {
                    return false
                }
            }
        }
    }
}
