//
//  CustomEmojiSettingsView.swift
//  damus
//
//  Created for NIP-30 custom emoji management.
//

import SwiftUI
import Kingfisher

/// Settings view for managing custom emoji collection.
///
/// Displays saved emojis with options to add new ones or remove existing.
struct CustomEmojiSettingsView: View {
    @ObservedObject var settings: UserSettingsStore
    @ObservedObject var custom_emojis: CustomEmojiStore
    let damus_state: DamusState

    @State private var showingAddEmoji = false
    @State private var emojiToDelete: CustomEmoji?

    init(settings: UserSettingsStore, damus_state: DamusState) {
        self.settings = settings
        self.damus_state = damus_state
        self.custom_emojis = damus_state.custom_emojis
    }

    var body: some View {
        List {
            Section {
                addEmojiButton
            }

            Section {
                if custom_emojis.savedCount == 0 {
                    emptyStateView
                } else {
                    ForEach(custom_emojis.sortedSavedEmojis, id: \.shortcode) { emoji in
                        emojiRow(emoji)
                    }
                    .onDelete(perform: deleteEmojis)
                }
            } header: {
                Text("My Emojis (\(custom_emojis.savedCount))", comment: "Section header for saved custom emojis")
            } footer: {
                Text("Custom emojis are stored in your kind 10030 emoji list and synced across Nostr clients.", comment: "Footer explaining custom emoji storage")
            }

            Section {
                clearRecentButton
            } header: {
                Text("Recent Emojis (\(custom_emojis.recentCount))", comment: "Section header for recent emojis")
            } footer: {
                Text("Recent emojis are collected from notes you view and are not synced.", comment: "Footer explaining recent emojis")
            }
        }
        .navigationTitle(NSLocalizedString("Custom Emoji", comment: "Title for custom emoji settings"))
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            EditButton()
        }
        .sheet(isPresented: $showingAddEmoji) {
            AddCustomEmojiView(damus_state: damus_state)
        }
        .alert(item: $emojiToDelete) { emoji in
            Alert(
                title: Text("Remove Emoji", comment: "Alert title for removing emoji"),
                message: Text("Remove :\(emoji.shortcode): from your collection?", comment: "Alert message for removing emoji"),
                primaryButton: .destructive(Text("Remove", comment: "Button to remove emoji")) {
                    removeEmoji(emoji)
                },
                secondaryButton: .cancel()
            )
        }
    }

    // MARK: - Subviews

    private var addEmojiButton: some View {
        Button {
            showingAddEmoji = true
        } label: {
            Label(
                NSLocalizedString("Add Custom Emoji", comment: "Button to add a new custom emoji"),
                systemImage: "plus.circle.fill"
            )
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Text("No custom emojis yet", comment: "Empty state title for custom emoji settings")
                .foregroundColor(.secondary)
            Text("Tap \"Add Custom Emoji\" to upload your own, or save emojis from notes you view.", comment: "Empty state description")
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 20)
    }

    private func emojiRow(_ emoji: CustomEmoji) -> some View {
        HStack(spacing: 12) {
            KFImage(emoji.url)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(":\(emoji.shortcode):")
                    .font(.body)
                Text(emoji.url.absoluteString)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .contextMenu {
            Button(role: .destructive) {
                emojiToDelete = emoji
            } label: {
                Label("Remove", systemImage: "trash")
            }

            Button {
                UIPasteboard.general.string = ":\(emoji.shortcode):"
            } label: {
                Label("Copy Shortcode", systemImage: "doc.on.doc")
            }

            Button {
                UIPasteboard.general.string = emoji.url.absoluteString
            } label: {
                Label("Copy URL", systemImage: "link")
            }
        }
    }

    private var clearRecentButton: some View {
        Button(role: .destructive) {
            damus_state.custom_emojis.clearRecent()
        } label: {
            Text("Clear Recent Emojis", comment: "Button to clear recent emojis")
        }
        .disabled(damus_state.custom_emojis.recentCount == 0)
    }

    // MARK: - Actions

    private func deleteEmojis(at offsets: IndexSet) {
        let emojis = damus_state.custom_emojis.sortedSavedEmojis
        Task { @MainActor in
            for index in offsets {
                let emoji = emojis[index]
                damus_state.custom_emojis.unsave(emoji)
            }
            // Publish once after all deletions
            await damus_state.custom_emojis.publishEmojiList(damus_state: damus_state)
        }
    }

    private func removeEmoji(_ emoji: CustomEmoji) {
        Task { @MainActor in
            damus_state.custom_emojis.unsave(emoji)
            await damus_state.custom_emojis.publishEmojiList(damus_state: damus_state)
        }
    }
}

// MARK: - CustomEmoji Identifiable conformance for alert

extension CustomEmoji: Identifiable {
    public var id: String { shortcode }
}

#Preview {
    NavigationView {
        CustomEmojiSettingsView(settings: UserSettingsStore(), damus_state: test_damus_state)
    }
}
