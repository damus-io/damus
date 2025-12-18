//
//  AddBlossomServerView.swift
//  damus
//
//  Created by Claude on 2025-01-15.
//
//  Sheet view for adding or changing a Blossom server URL.
//
//  Provides URL validation and clipboard paste functionality.
//  Only accepts valid http/https URLs with a host component.
//

import SwiftUI

// MARK: - Add Blossom Server View

/// Sheet for adding or changing a Blossom server URL.
///
/// Features:
/// - Text field with URL validation
/// - Paste from clipboard button
/// - Clear error feedback for invalid URLs
struct AddBlossomServerView: View {
    @ObservedObject var settings: UserSettingsStore
    @Environment(\.dismiss) var dismiss

    /// The URL being entered by the user
    @State private var urlText: String = ""

    /// Validation error message, if any
    @State private var errorMessage: String?

    /// Whether the save button is enabled
    private var canSave: Bool {
        !urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section(
                    header: Text("Server URL", comment: "Section header for Blossom server URL input"),
                    footer: serverSectionFooter
                ) {
                    TextField(
                        "https://blossom.example.com",
                        text: $urlText
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onChange(of: urlText) { _ in
                        // Clear error when user starts typing
                        errorMessage = nil
                    }

                    // Paste from clipboard button
                    if UIPasteboard.general.hasStrings {
                        Button(action: pasteFromClipboard) {
                            Label(
                                NSLocalizedString("Paste from Clipboard", comment: "Button to paste URL from clipboard"),
                                systemImage: "doc.on.clipboard"
                            )
                        }
                    }
                }

                // Error display
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

                // Server examples/suggestions
                Section(
                    header: Text("Public Servers", comment: "Section header for example Blossom servers")
                ) {
                    Text("Some public Blossom servers you can try:", comment: "Intro text for public server examples")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    ForEach(exampleServers, id: \.self) { server in
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
                    }
                }
            }
            .navigationTitle(NSLocalizedString("Add Blossom Server", comment: "Navigation title for adding a Blossom server"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Cancel", comment: "Cancel button")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Save", comment: "Save button")) {
                        saveServer()
                    }
                    .disabled(!canSave)
                }
            }
            .onAppear {
                // Pre-fill with current server if editing
                if let current = settings.manualBlossomServerUrl {
                    urlText = current
                }
            }
        }
    }

    // MARK: - Computed Properties

    /// Footer for the server URL section.
    private var serverSectionFooter: some View {
        Text("Enter the full URL of a Blossom-compatible media server.", comment: "Help text for entering a Blossom server URL")
    }

    /// Example public Blossom servers users can try.
    private var exampleServers: [String] {
        [
            "https://blossom.primal.net",
            "https://nostr.download",
            "https://blossom.oxtr.dev",
            "https://cdn.satellite.earth"
        ]
    }

    // MARK: - Actions

    /// Pastes the URL from the system clipboard.
    private func pasteFromClipboard() {
        guard let clipboardString = UIPasteboard.general.string else { return }
        urlText = clipboardString.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Validates and saves the server URL.
    private func saveServer() {
        let trimmedURL = urlText.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate URL format
        guard let serverURL = BlossomServerURL(trimmedURL) else {
            errorMessage = NSLocalizedString(
                "Invalid URL. Please enter a valid http or https URL.",
                comment: "Error shown when user enters an invalid Blossom server URL"
            )
            return
        }

        // Save the validated URL
        settings.manualBlossomServerUrl = serverURL.absoluteString
        dismiss()
    }
}

// MARK: - Preview

#Preview {
    AddBlossomServerView(settings: UserSettingsStore())
}
