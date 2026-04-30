//
//  PrivacySettingsView.swift
//  damus
//
//  Created for privacy and data collection settings
//

import Foundation
import SwiftUI
import Sentry

struct PrivacySettingsView: View {
    @ObservedObject var globalSettings = GlobalSettingsStore.shared
    @State private var isShowingPrivacyDetails = false
    
    var body: some View {
        Form {
            Section(
                header: Text("Error & Diagnostics Reporting", comment: "Section header for error and diagnostics reporting settings"),
                footer: VStack(alignment: .leading, spacing: 8) {
                    Text("Sentry provides reporting for crashes, errors, and app health issues. When enabled, anonymous technical data is sent to help improve the app. No personal information or private keys are collected. This setting applies to the entire app on this device and is not tied to a specific account. Restart the app for changes to take effect.", comment: "Footer explaining Sentry telemetry")
                    Button(NSLocalizedString("Learn more", comment: "Button title to show more details about privacy and data handling")) {
                        isShowingPrivacyDetails = true
                    }
                    .font(.footnote)
                }
            ) {
                Toggle(NSLocalizedString("Enable Error & Diagnostics Reporting", comment: "Setting to enable Sentry error and diagnostics reporting"), isOn: $globalSettings.enable_sentry_telemetry)
                    .toggleStyle(.switch)
            }
        }
        .navigationTitle(NSLocalizedString("Privacy", comment: "Navigation title for Privacy settings"))
        .sheet(isPresented: $isShowingPrivacyDetails) {
            PrivacyDataHandlingDetailsView()
        }
    }
}

/// Presents additional context about diagnostics reporting and the data shared with Sentry.
struct PrivacyDataHandlingDetailsView: View {
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            List {
                Section {
                    Text("When diagnostics reporting is enabled, Damus sends anonymous technical information to Sentry so crashes, errors, and app stability problems can be investigated and fixed faster.", comment: "Overview of diagnostics reporting and why it exists")
                } header: {
                    Text("How it works", comment: "Section title describing how diagnostics reporting works")
                }
                
                Section {
                    PrivacyInfoRow(
                        icon: "chart.bar.xaxis",
                        title: NSLocalizedString("What is shared", comment: "Title for information about data that is shared"),
                        description: NSLocalizedString("Crash reports, error messages, app version, iOS version, device model, and basic performance diagnostics.", comment: "Description of shared diagnostics data")
                    )
                    PrivacyInfoRow(
                        icon: "hand.raised.fill",
                        title: NSLocalizedString("What is not shared", comment: "Title for information about data that is not shared"),
                        description: NSLocalizedString("Private keys, seed phrases, wallet secrets, direct message contents, and profile content you create in the app.", comment: "Description of private data that is not shared")
                    )
                    PrivacyInfoRow(
                        icon: "switch.2",
                        title: NSLocalizedString("Your control", comment: "Title for information about user control over diagnostics reporting"),
                        description: NSLocalizedString("You can turn diagnostics reporting on or off at any time from Privacy settings. Changes apply after restarting the app. Turning it off stops future reports from being sent, but does not delete reports that were already sent.", comment: "Description of user control over diagnostics reporting")
                    )
                } header: {
                    Text("Data handling details", comment: "Section title for detailed data handling information")
                }
                
                Section {
                    CollectedDataRow(
                        title: NSLocalizedString("Crash and exception details", comment: "Title for crash and exception details row"),
                        description: NSLocalizedString("Technical stack traces and failure context used to debug app issues.", comment: "Description for crash and exception details row"),
                        collected: true
                    )
                    CollectedDataRow(
                        title: NSLocalizedString("Device and app metadata", comment: "Title for device and app metadata row"),
                        description: NSLocalizedString("Information such as app version, operating system version, and device type.", comment: "Description for device and app metadata row"),
                        collected: true
                    )
                    CollectedDataRow(
                        title: NSLocalizedString("Messages, notes, and private keys", comment: "Title for sensitive data row"),
                        description: NSLocalizedString("Personal content and credentials are not intentionally collected for diagnostics reporting. Damus is designed not to send sensitive information such as private keys, public keys, or email addresses, and it also automatically detects and redacts those patterns as an additional safeguard before reports are sent.", comment: "Description for sensitive data row"),
                        collected: false
                    )
                } header: {
                    Text("Collected data summary", comment: "Section title summarizing collected data")
                }
            }
            .navigationTitle(NSLocalizedString("Diagnostics Privacy", comment: "Navigation title for the privacy details sheet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(NSLocalizedString("Done", comment: "Button to dismiss privacy details sheet")) {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct PrivacyInfoRow: View {
    let icon: String
    let title: String
    let description: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.green)
                .font(.system(size: 20))
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct CollectedDataRow: View {
    let title: String
    let description: String
    let collected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: collected ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(collected ? .blue : .gray)
                .font(.system(size: 20))
                .frame(width: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                
                Text(description)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

// MARK: - Preview

struct PrivacySettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            PrivacySettingsView()
        }
    }
}
