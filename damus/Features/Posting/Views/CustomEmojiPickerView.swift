//
//  CustomEmojiPickerView.swift
//  damus
//
//  Created for NIP-30 custom emoji compose support.
//

import SwiftUI
import Kingfisher

/// A view for selecting custom emojis during post composition.
struct CustomEmojiPickerView: View {
    let damus_state: DamusState
    let onSelect: (CustomEmoji) -> Void

    @Environment(\.dismiss) var dismiss
    @State private var searchText: String = ""
    @State private var selectedTab: EmojiTab = .saved

    enum EmojiTab: String, CaseIterable {
        case saved = "My Emojis"
        case recent = "Recent"
    }

    private var filteredEmojis: [CustomEmoji] {
        switch selectedTab {
        case .saved:
            return damus_state.custom_emojis.searchSaved(searchText)
        case .recent:
            return damus_state.custom_emojis.searchRecent(searchText)
        }
    }

    private var hasAnyEmojis: Bool {
        damus_state.custom_emojis.savedCount > 0 || damus_state.custom_emojis.recentCount > 0
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if !hasAnyEmojis {
                    emptyStateView
                } else {
                    tabPicker
                    searchBar
                    emojiGrid
                }
            }
            .navigationTitle(NSLocalizedString("Custom Emoji", comment: "Title for custom emoji picker"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(NSLocalizedString("Cancel", comment: "Button to cancel custom emoji selection")) {
                        dismiss()
                    }
                }
            }
        }
    }

    private var tabPicker: some View {
        Picker("Emoji Source", selection: $selectedTab) {
            ForEach(EmojiTab.allCases, id: \.self) { tab in
                Text(tabLabel(tab)).tag(tab)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func tabLabel(_ tab: EmojiTab) -> String {
        switch tab {
        case .saved:
            let count = damus_state.custom_emojis.savedCount
            return count > 0 ? "\(tab.rawValue) (\(count))" : tab.rawValue
        case .recent:
            let count = damus_state.custom_emojis.recentCount
            return count > 0 ? "\(tab.rawValue) (\(count))" : tab.rawValue
        }
    }

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "face.smiling")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No custom emoji found", comment: "Message shown when no custom emojis are available")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Custom emoji will appear here as you browse notes that use them. Long-press an emoji to save it to your collection.", comment: "Explanation for empty custom emoji state")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var searchBar: some View {
        HStack {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField(NSLocalizedString("Search emoji", comment: "Placeholder for custom emoji search"), text: $searchText)
                .textFieldStyle(.plain)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(10)
        .background(Color(.systemGray6))
        .cornerRadius(10)
        .padding()
    }

    private var emojiGrid: some View {
        ScrollView {
            if filteredEmojis.isEmpty {
                emptyTabView
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 12) {
                    ForEach(filteredEmojis, id: \.shortcode) { emoji in
                        emojiCell(emoji)
                    }
                }
                .padding()
            }
        }
    }

    private var emptyTabView: some View {
        VStack(spacing: 12) {
            if selectedTab == .saved {
                Text("No saved emojis yet", comment: "Message when user has no saved emojis")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Long-press an emoji in Recent to save it", comment: "Hint for saving emojis")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                Text("No recent emojis", comment: "Message when no recent emojis")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Text("Browse notes with custom emojis to see them here", comment: "Hint for finding emojis")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 200)
        .padding()
    }

    private func emojiCell(_ emoji: CustomEmoji) -> some View {
        let isSaved = damus_state.custom_emojis.isSaved(emoji)

        return Button(action: {
            onSelect(emoji)
            dismiss()
        }) {
            VStack(spacing: 4) {
                ZStack(alignment: .topTrailing) {
                    KFImage(emoji.url)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)

                    if isSaved {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundColor(.yellow)
                            .offset(x: 4, y: -4)
                    }
                }

                Text(":\(emoji.shortcode):")
                    .font(.caption2)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(.primary)
            }
            .frame(width: 70, height: 60)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
        .buttonStyle(.plain)
        .contextMenu {
            if isSaved {
                Button(role: .destructive) {
                    unsaveEmoji(emoji)
                } label: {
                    Label("Remove from My Emojis", systemImage: "star.slash")
                }
            } else {
                Button {
                    saveEmoji(emoji)
                } label: {
                    Label("Save to My Emojis", systemImage: "star")
                }
            }
        }
    }

    private func saveEmoji(_ emoji: CustomEmoji) {
        Task { @MainActor in
            damus_state.custom_emojis.save(emoji)
            await damus_state.custom_emojis.publishEmojiList(damus_state: damus_state)
        }
    }

    private func unsaveEmoji(_ emoji: CustomEmoji) {
        Task { @MainActor in
            damus_state.custom_emojis.unsave(emoji)
            await damus_state.custom_emojis.publishEmojiList(damus_state: damus_state)
        }
    }
}

#Preview {
    CustomEmojiPickerView(damus_state: test_damus_state) { emoji in
        print("Selected: \(emoji.shortcode)")
    }
}
