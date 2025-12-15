//
//  MediaServerSettingsView.swift
//  damus
//
//  Created by Claude on 2025-01-15.
//
//  Settings view for configuring media upload servers.
//
//  This view allows users to:
//  - Select their default media uploader (nostr.build, nostrcheck, Blossom)
//  - Configure a Blossom server URL when Blossom is selected
//
//  For Blossom, users can manually enter a server URL which is stored
//  in settings. Kind 10063 server list support may be added later.
//

import SwiftUI

// MARK: - Media Server Settings View

/// Settings view for configuring media upload servers.
///
/// Provides UI for:
/// - Selecting default media uploader
/// - Configuring Blossom server URL (when Blossom selected)
struct MediaServerSettingsView: View {
    let damus_state: DamusState
    @ObservedObject var settings: UserSettingsStore
    @Environment(\.dismiss) var dismiss

    /// Whether the add server sheet is showing
    @State private var showingAddServerSheet = false

    var body: some View {
        Form {
            // MARK: - Default Uploader Section
            Section(
                header: Text("Default Uploader", comment: "Section header for selecting the default media uploader"),
                footer: Text("Choose which service to use when uploading images and videos.", comment: "Footer explaining the default uploader setting")
            ) {
                Picker(
                    NSLocalizedString("Media uploader", comment: "Label for media uploader picker"),
                    selection: $settings.default_media_uploader
                ) {
                    ForEach(MediaUploader.allCases, id: \.self) { uploader in
                        Text(uploader.model.displayName)
                            .tag(uploader)
                    }
                }
            }

            // MARK: - Blossom Server Section
            // Only show when Blossom is selected as the uploader
            if settings.default_media_uploader == .blossom {
                Section(
                    header: Text("Blossom Server", comment: "Section header for Blossom server configuration"),
                    footer: blossomSectionFooter
                ) {
                    if let serverURL = currentBlossomServer {
                        // Show current server with option to change
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Current Server", comment: "Label for the currently configured Blossom server")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(serverURL.absoluteString)
                                    .font(.body)
                            }
                            Spacer()
                        }

                        Button(action: { showingAddServerSheet = true }) {
                            Text("Change Server", comment: "Button to change the Blossom server")
                        }

                        Button(role: .destructive, action: clearServer) {
                            Text("Remove Server", comment: "Button to remove the configured Blossom server")
                        }
                    } else {
                        // No server configured - show prompt to add one
                        VStack(alignment: .leading, spacing: 8) {
                            Text("No server configured", comment: "Text shown when no Blossom server is configured")
                                .foregroundColor(.secondary)

                            Button(action: { showingAddServerSheet = true }) {
                                Label(
                                    NSLocalizedString("Add Server", comment: "Button to add a Blossom server"),
                                    systemImage: "plus.circle"
                                )
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Media Servers", comment: "Navigation title for media server settings"))
        .sheet(isPresented: $showingAddServerSheet) {
            AddBlossomServerView(settings: settings)
        }
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
        }
    }

    // MARK: - Computed Properties

    /// The currently configured Blossom server URL, if any.
    private var currentBlossomServer: BlossomServerURL? {
        guard let urlString = settings.manualBlossomServerUrl,
              !urlString.isEmpty else {
            return nil
        }
        return BlossomServerURL(urlString)
    }

    /// Footer text for the Blossom server section.
    private var blossomSectionFooter: some View {
        Text("Blossom servers store your media files. Enter the URL of a Blossom-compatible server.", comment: "Footer explaining what Blossom servers do")
    }

    // MARK: - Actions

    /// Clears the configured Blossom server.
    private func clearServer() {
        settings.manualBlossomServerUrl = nil
    }
}

// MARK: - Preview

#Preview {
    NavigationStack {
        MediaServerSettingsView(
            damus_state: test_damus_state,
            settings: UserSettingsStore()
        )
    }
}
