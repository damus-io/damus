//
//  SpellDiscoveryView.swift
//  damus
//
//  Sheet for browsing and adding spell feeds.
//

import SwiftUI

struct SpellDiscoveryView: View {
    let damus_state: DamusState
    @ObservedObject var feedTabStore: FeedTabStore
    @StateObject private var model: SpellDiscoveryModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var showFilterBuilder = false
    @State private var showManagement = false

    init(damus_state: DamusState, feedTabStore: FeedTabStore) {
        self.damus_state = damus_state
        self.feedTabStore = feedTabStore
        self._model = StateObject(wrappedValue: SpellDiscoveryModel(damus_state: damus_state))
    }

    private var filteredSpells: [DiscoveredSpell] {
        if searchText.isEmpty {
            return model.spells
        }
        let query = searchText.lowercased()
        return model.spells.filter { $0.displayName.lowercased().contains(query) }
    }

    private func isAlreadyAdded(_ spell: DiscoveredSpell) -> Bool {
        feedTabStore.savedFeeds.contains { $0.id == spell.noteId.hex() }
    }

    var body: some View {
        NavigationView {
            Group {
                if model.isLoading && model.spells.isEmpty {
                    loadingView
                } else if filteredSpells.isEmpty {
                    emptyView
                } else {
                    spellList
                }
            }
            .navigationTitle(NSLocalizedString("Discover Feeds", comment: "Title for the spell feed discovery sheet"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(NSLocalizedString("Done", comment: "Button to dismiss the feed discovery sheet")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button {
                            showManagement = true
                        } label: {
                            Image(systemName: "list.bullet")
                        }
                        .accessibilityLabel(NSLocalizedString("Manage feeds", comment: "Button to open feed management"))

                        Button {
                            showFilterBuilder = true
                        } label: {
                            Image(systemName: "plus.circle")
                        }
                        .accessibilityLabel(NSLocalizedString("Create custom feed", comment: "Button to open filter builder"))
                    }
                }
            }
            .sheet(isPresented: $showFilterBuilder) {
                FilterBuilderView { savedFeed in
                    feedTabStore.addFeed(savedFeed)
                }
            }
            .sheet(isPresented: $showManagement) {
                FeedManagementView(store: feedTabStore)
            }
            .searchable(
                text: $searchText,
                prompt: NSLocalizedString("Search feeds", comment: "Placeholder for feed discovery search field")
            )
        }
        .onAppear {
            model.load()
        }
        .onDisappear {
            model.cancel()
        }
    }

    // MARK: - Subviews

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Searching for feeds...", comment: "Loading state for feed discovery")
                .foregroundColor(.secondary)
                .font(.callout)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 35))
                .foregroundColor(.gray)
            if searchText.isEmpty {
                Text("No feeds found", comment: "Empty state when no spell feeds are found on relays")
                    .font(.callout.weight(.medium))
                    .foregroundColor(.gray)
            } else {
                Text("No feeds matching \"\(searchText)\"", comment: "Empty state when search yields no results")
                    .font(.callout.weight(.medium))
                    .foregroundColor(.gray)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var spellList: some View {
        List(filteredSpells) { discovered in
            SpellDiscoveryRow(
                damus_state: damus_state,
                discovered: discovered,
                isAdded: isAlreadyAdded(discovered),
                onAdd: {
                    feedTabStore.addFeed(discovered.toSavedFeed())
                }
            )
        }
        .listStyle(.plain)
    }
}

// MARK: - Row

struct SpellDiscoveryRow: View {
    let damus_state: DamusState
    let discovered: DiscoveredSpell
    let isAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(discovered.displayName)
                    .font(.body.weight(.medium))
                    .lineLimit(1)

                let description = discovered.spell.displayDescription
                if !description.isEmpty {
                    Text(description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 4) {
                    spellSummary
                }
                .font(.caption2)
                .foregroundColor(.gray)
            }

            Spacer()

            Button(action: onAdd) {
                if isAdded {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.green)
                } else {
                    Image(systemName: "plus.circle.fill")
                        .font(.system(size: 22))
                        .foregroundColor(DamusColors.purple)
                }
            }
            .disabled(isAdded)
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
    }

    private var spellSummary: some View {
        let parts = discovered.spell.kinds.prefix(3).map { "kind:\($0)" }
        let text = parts.joined(separator: ", ")
        return Text(text)
    }
}
