//
//  SafariExtensionSettingsView.swift
//  damus
//
//  Created by alltheseas on 2026-01-05.
//

import SwiftUI

/// Settings view for the Damoose Safari extension.
///
/// Guides users through enabling the NIP-07 browser extension
/// in Safari settings.
struct SafariExtensionSettingsView: View {
    var body: some View {
        Form {
            Section(header: Text("About")) {
                Text("Damoose is Damus's NIP-07 browser extension for Safari. It allows nostr websites to request signatures from your Damus wallet.")
                    .font(.body)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Enable Extension")) {
                VStack(alignment: .leading, spacing: 12) {
                    instructionRow(number: 1, text: "Open the Settings app")
                    instructionRow(number: 2, text: "Tap Safari")
                    instructionRow(number: 3, text: "Tap Extensions")
                    instructionRow(number: 4, text: "Find Damoose and enable it")
                    instructionRow(number: 5, text: "Set permission to \"Allow\" for all websites")
                }
                .padding(.vertical, 8)
            }

            Section(header: Text("Open Safari Settings")) {
                Button(action: openSafariSettings) {
                    HStack {
                        Image(systemName: "gear")
                        Text("Open Settings")
                    }
                }
            }

            Section(header: Text("Permissions")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("When you approve a signing request with \"Remember this permission\" checked, Damoose will automatically approve future requests of the same type from that website.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.vertical, 4)
            }
        }
        .navigationTitle("Safari Extension")
        .navigationBarTitleDisplayMode(.large)
    }

    private func instructionRow(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number).")
                .font(.body.weight(.semibold))
                .foregroundColor(.accentColor)
                .frame(width: 24, alignment: .trailing)
            Text(text)
                .font(.body)
        }
    }

    private func openSafariSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

struct SafariExtensionSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            SafariExtensionSettingsView()
        }
    }
}
