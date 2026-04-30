//
//  MediaServersSettingsView.swift
//  damus
//
//  Created by Claude on 2026-03-18.
//

import SwiftUI

struct MediaServersSettingsView: View {
    @ObservedObject var settings: UserSettingsStore
    @Environment(\.dismiss) var dismiss

    init(settings: UserSettingsStore) {
        _settings = ObservedObject(initialValue: settings)
    }

    var body: some View {
        Form {
            Section(header: Text(NSLocalizedString("Upload Service", comment: "Section header for media upload service selection"))) {
                Picker(NSLocalizedString("Media uploader", comment: "Prompt selection of media upload service"),
                       selection: $settings.default_media_uploader) {
                    ForEach(MediaUploader.allCases, id: \.self) { uploader in
                        Text(uploader.model.displayName)
                            .tag(uploader.model.tag)
                    }
                }
            }

            if settings.default_media_uploader.isBlossom {
                Section(
                    header: Text(NSLocalizedString("Blossom Server", comment: "Section header for Blossom server configuration")),
                    footer: Text(NSLocalizedString("HTTPS URL of your Blossom media server. Files are stored as content-addressed blobs identified by SHA-256 hash.", comment: "Footer explaining Blossom server setting"))
                ) {
                    TextField("https://blossom.nostr.build", text: $settings.blossom_server_url)
                        .autocorrectionDisabled(true)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)

                    if let server = BlossomServerURL(string: settings.blossom_server_url) {
                        Label(NSLocalizedString("Valid server URL", comment: "Label indicating the Blossom server URL is valid"), systemImage: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else if !settings.blossom_server_url.isEmpty {
                        Label(NSLocalizedString("Invalid URL (must be HTTPS)", comment: "Label indicating the Blossom server URL is invalid"), systemImage: "xmark.circle.fill")
                            .foregroundColor(.red)
                    }
                }
            }
        }
        .navigationTitle(NSLocalizedString("Media Servers", comment: "Navigation title for media server settings"))
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
        }
    }
}

#Preview {
    NavigationView {
        MediaServersSettingsView(settings: test_damus_state.settings)
    }
}
