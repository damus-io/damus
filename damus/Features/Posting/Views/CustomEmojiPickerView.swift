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

    private var filteredEmojis: [CustomEmoji] {
        damus_state.custom_emojis.search(searchText)
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                if damus_state.custom_emojis.count == 0 {
                    emptyStateView
                } else {
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

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "face.smiling")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("No custom emoji found", comment: "Message shown when no custom emojis are available")
                .font(.headline)
                .foregroundColor(.secondary)
            Text("Custom emoji will appear here as you browse notes that use them.", comment: "Explanation for empty custom emoji state")
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
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 70))], spacing: 12) {
                ForEach(filteredEmojis, id: \.shortcode) { emoji in
                    emojiCell(emoji)
                }
            }
            .padding()
        }
    }

    private func emojiCell(_ emoji: CustomEmoji) -> some View {
        Button(action: {
            onSelect(emoji)
            dismiss()
        }) {
            VStack(spacing: 4) {
                KFImage(emoji.url)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 32, height: 32)

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
    }
}

#Preview {
    CustomEmojiPickerView(damus_state: test_damus_state) { emoji in
        print("Selected: \(emoji.shortcode)")
    }
}
