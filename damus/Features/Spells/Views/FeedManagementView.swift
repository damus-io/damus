//
//  FeedManagementView.swift
//  damus
//
//  View for managing saved spell feeds: reorder, rename, and delete.
//

import SwiftUI

/// A list-based view for managing saved spell feeds.
///
/// Supports drag-to-reorder, inline renaming, and swipe-to-delete.
/// Accessed from the SpellDiscoveryView or a settings entry point.
struct FeedManagementView: View {
    @ObservedObject var store: FeedTabStore
    @Environment(\.dismiss) private var dismiss
    @State private var editingFeedId: String?
    @State private var editingName: String = ""

    var body: some View {
        NavigationView {
            Group {
                if store.savedFeeds.isEmpty {
                    emptyState
                } else {
                    feedList
                }
            }
            .navigationTitle(NSLocalizedString("Manage Feeds", comment: "Title for feed management view"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(NSLocalizedString("Done", comment: "Done button")) {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Feed List

    private var feedList: some View {
        List {
            Section(
                footer: Text("Drag to reorder. Swipe left to delete.", comment: "Footer hint for feed management")
            ) {
                ForEach(store.savedFeeds) { feed in
                    feedRow(feed)
                }
                .onMove { source, destination in
                    store.moveFeed(from: source, to: destination)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        store.removeFeed(id: store.savedFeeds[index].id)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .environment(\.editMode, .constant(.active))
    }

    // MARK: - Feed Row

    private func feedRow(_ feed: SavedSpellFeed) -> some View {
        HStack {
            if editingFeedId == feed.id {
                TextField(
                    NSLocalizedString("Feed name", comment: "Placeholder for renaming a feed"),
                    text: $editingName,
                    onCommit: {
                        commitRename(feed)
                    }
                )
                .textFieldStyle(.roundedBorder)

                Button(NSLocalizedString("Save", comment: "Save rename button")) {
                    commitRename(feed)
                }
                .buttonStyle(.borderless)
                .foregroundColor(DamusColors.purple)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    Text(feed.name)
                        .font(.body)
                    if let spell = feed.parseSpell() {
                        Text(spellSummary(spell))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Spacer()

                Button {
                    editingFeedId = feed.id
                    editingName = feed.name
                } label: {
                    Image(systemName: "pencil")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 35))
                .foregroundColor(.gray)
            Text("No custom feeds yet", comment: "Empty state for feed management")
                .font(.callout.weight(.medium))
                .foregroundColor(.gray)
            Text("Add feeds from the Discover screen or create your own.", comment: "Empty state help text")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func commitRename(_ feed: SavedSpellFeed) {
        let trimmed = editingName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty {
            store.renameFeed(id: feed.id, newName: trimmed)
        }
        editingFeedId = nil
    }

    private func spellSummary(_ spell: SpellEvent) -> String {
        let parts = spell.kinds.prefix(3).map { "kind:\($0)" }
        return parts.joined(separator: ", ")
    }
}
