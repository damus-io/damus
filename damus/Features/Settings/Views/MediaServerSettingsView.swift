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
//  - Configure mirror servers for redundancy
//  - Publish kind 10063 server list to relays (BUD-03)
//

import SwiftUI

// MARK: - Media Server Settings View

/// Settings view for configuring media upload servers.
///
/// Provides UI for:
/// - Selecting default media uploader
/// - Configuring Blossom server URL (when Blossom selected)
/// - Configuring Blossom mirror servers for redundancy
/// - Publishing kind 10063 server list to relays
struct MediaServerSettingsView: View {
    let damus_state: DamusState
    @ObservedObject var settings: UserSettingsStore
    @Environment(\.dismiss) var dismiss

    /// Whether the add server sheet is showing
    @State private var showingAddServerSheet = false

    /// Whether the add mirror server sheet is showing
    @State private var showingAddMirrorServerSheet = false

    /// Whether we're currently publishing the server list
    @State private var isPublishing = false

    /// Status message for publish operation
    @State private var publishStatus: String?

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

                // MARK: - Mirror Settings Section
                Section(
                    header: Text("Backup Mirrors", comment: "Section header for Blossom mirror settings"),
                    footer: Text("When enabled, uploads are automatically copied to backup servers for redundancy.", comment: "Footer explaining mirror feature")
                ) {
                    Toggle(
                        NSLocalizedString("Enable Mirroring", comment: "Toggle to enable Blossom mirroring"),
                        isOn: $settings.blossomMirrorEnabled
                    )

                    if settings.blossomMirrorEnabled {
                        // Show configured mirror servers
                        if !settings.blossomMirrorServers.isEmpty {
                            ForEach(settings.blossomMirrorServers, id: \.self) { server in
                                HStack {
                                    Text(server)
                                        .font(.body)
                                    Spacer()
                                }
                            }
                            .onDelete(perform: deleteMirrorServer)
                        }

                        Button(action: { showingAddMirrorServerSheet = true }) {
                            Label(
                                NSLocalizedString("Add Mirror Server", comment: "Button to add a mirror server"),
                                systemImage: "plus.circle"
                            )
                        }
                    }
                }

                // MARK: - Publish Server List Section
                Section(
                    header: Text("Publish Server List", comment: "Section header for publishing server list"),
                    footer: Text("Publishing your server list (kind 10063) lets other clients find your media if your primary server is unavailable.", comment: "Footer explaining server list publication")
                ) {
                    // Show current server list that would be published
                    if let primary = currentBlossomServer {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Servers to publish:", comment: "Label for servers that will be published")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Text("1. \(primary.absoluteString)")
                                .font(.caption2)
                                .foregroundColor(.primary)

                            ForEach(Array(settings.blossomMirrorServers.enumerated()), id: \.element) { index, server in
                                Text("\(index + 2). \(server)")
                                    .font(.caption2)
                                    .foregroundColor(.primary)
                            }
                        }
                        .padding(.vertical, 4)

                        Button(action: publishServerList) {
                            HStack {
                                if isPublishing {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                } else {
                                    Image(systemName: "paperplane")
                                }
                                Text("Publish to Relays", comment: "Button to publish server list to relays")
                            }
                        }
                        .disabled(isPublishing)

                        if let status = publishStatus {
                            Text(status)
                                .font(.caption)
                                .foregroundColor(status.contains("✓") ? .green : .red)
                        }
                    } else {
                        Text("Configure a primary server first", comment: "Message shown when no primary server is configured")
                            .foregroundColor(.secondary)
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Media Servers", comment: "Navigation title for media server settings"))
        .sheet(isPresented: $showingAddServerSheet) {
            AddBlossomServerView(settings: settings)
        }
        .sheet(isPresented: $showingAddMirrorServerSheet) {
            AddBlossomMirrorServerView(settings: settings)
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

    /// Deletes mirror servers at the specified indices.
    private func deleteMirrorServer(at offsets: IndexSet) {
        var servers = settings.blossomMirrorServers
        servers.remove(atOffsets: offsets)
        settings.blossomMirrorServers = servers
    }

    /// Publishes the current server list as a kind 10063 event to relays (BUD-03).
    /// The event contains all configured servers in order: primary first, then mirrors.
    private func publishServerList() {
        guard let primary = currentBlossomServer else { return }

        isPublishing = true
        publishStatus = nil

        Task {
            do {
                // Build ordered server list: primary server first, then all mirror servers
                let mirrorServers = settings.blossomMirrorServers.compactMap { BlossomServerURL($0) }
                let allServers = [primary] + mirrorServers
                let serverList = BlossomServerList(servers: allServers)

                // Sign the event with user's keypair
                guard let fullKeypair = damus_state.keypair.to_full() else {
                    throw BlossomServerListManagerError.noPrivateKey
                }

                guard let event = serverList.toNostrEvent(keypair: fullKeypair) else {
                    throw BlossomServerListManagerError.eventCreationFailed
                }

                // Broadcast to all connected relays
                await damus_state.nostrNetwork.postbox.send(event)

                // Cache event ID for local retrieval
                settings.latestBlossomServerListEventIdHex = event.id.hex()

                await MainActor.run {
                    isPublishing = false
                    publishStatus = "✓ Published to relays"
                }

                // Auto-clear success message after 3 seconds
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await MainActor.run {
                    publishStatus = nil
                }

            } catch {
                await MainActor.run {
                    isPublishing = false
                    publishStatus = "Failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Add Mirror Server View

/// Sheet for adding a Blossom mirror server URL.
struct AddBlossomMirrorServerView: View {
    @ObservedObject var settings: UserSettingsStore
    @Environment(\.dismiss) var dismiss

    @State private var urlText: String = ""
    @State private var errorMessage: String?

    private var canSave: Bool {
        !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    header: Text("Mirror Server URL", comment: "Section header for mirror server URL input"),
                    footer: Text("Enter the URL of a Blossom server to use as a backup mirror.", comment: "Help text for mirror server URL")
                ) {
                    TextField(
                        "https://blossom.example.com",
                        text: $urlText
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onChange(of: urlText) { _ in
                        errorMessage = nil
                    }

                    if UIPasteboard.general.hasStrings {
                        Button(action: pasteFromClipboard) {
                            Label(
                                NSLocalizedString("Paste from Clipboard", comment: "Button to paste URL from clipboard"),
                                systemImage: "doc.on.clipboard"
                            )
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .foregroundColor(.red)
                        }
                    }
                }

                // Suggested servers
                Section(
                    header: Text("Suggested Servers", comment: "Section header for suggested mirror servers")
                ) {
                    ForEach(suggestedMirrorServers, id: \.self) { server in
                        Button(action: { urlText = server }) {
                            HStack {
                                Text(server)
                                    .font(.body)
                                Spacer()
                                Image(systemName: "arrow.right.circle")
                                    .foregroundColor(.secondary)
                            }
                        }
                        .foregroundColor(.primary)
                        .disabled(settings.blossomMirrorServers.contains(server) || settings.manualBlossomServerUrl == server)
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Add Mirror Server", comment: "Navigation title for adding a mirror server"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "Cancel button")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Add", comment: "Add button")) {
                        addServer()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var suggestedMirrorServers: [String] {
        [
            "https://blossom.primal.net",
            "https://nostr.download",
            "https://blossom.oxtr.dev",
            "https://cdn.satellite.earth"
        ]
    }

    private func pasteFromClipboard() {
        guard let clipboardString = UIPasteboard.general.string else { return }
        urlText = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func addServer() {
        let trimmedURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)

        guard let serverURL = BlossomServerURL(trimmedURL) else {
            errorMessage = NSLocalizedString(
                "Invalid URL. Please enter a valid http or https URL.",
                comment: "Error shown when user enters an invalid server URL"
            )
            return
        }

        // Don't add if it's the primary server
        if settings.manualBlossomServerUrl == serverURL.absoluteString {
            errorMessage = NSLocalizedString(
                "This is already your primary server.",
                comment: "Error shown when trying to add primary server as mirror"
            )
            return
        }

        // Don't add duplicates
        if settings.blossomMirrorServers.contains(serverURL.absoluteString) {
            errorMessage = NSLocalizedString(
                "This server is already in your mirror list.",
                comment: "Error shown when trying to add duplicate mirror server"
            )
            return
        }

        var servers = settings.blossomMirrorServers
        servers.append(serverURL.absoluteString)
        settings.blossomMirrorServers = servers
        dismiss()
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
