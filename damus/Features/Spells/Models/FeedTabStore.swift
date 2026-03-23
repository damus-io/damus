//
//  FeedTabStore.swift
//  damus
//
//  Persists feed tab configuration (saved spell feeds, tab order,
//  selected tab) to UserDefaults.
//

import Foundation

/// Manages persistence and state for feed tabs.
///
/// Stores the user's saved spell feeds and tab selection.
/// Tab order is determined by the array order of saved feeds.
@MainActor
class FeedTabStore: ObservableObject {
    @Published private(set) var savedFeeds: [SavedSpellFeed] = []
    @Published var selectedTabId: String = "following"

    private let userDefaults: UserDefaults
    private static let savedFeedsKey = "spell_saved_feeds"
    private static let selectedTabKey = "spell_selected_tab"

    /// All available tabs: Following first, then saved spell feeds.
    var tabs: [FeedTab] {
        var result: [FeedTab] = [.following]
        for feed in savedFeeds {
            result.append(.spell(feed))
        }
        return result
    }

    /// The currently selected tab.
    var selectedTab: FeedTab {
        if selectedTabId == "following" {
            return .following
        }
        if let feed = savedFeeds.first(where: { $0.id == selectedTabId }) {
            return .spell(feed)
        }
        return .following
    }

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        loadSavedFeeds()
        loadSelectedTab()
    }

    /// Adds a spell feed to the saved list.
    func addFeed(_ feed: SavedSpellFeed) {
        guard !savedFeeds.contains(where: { $0.id == feed.id }) else { return }
        savedFeeds.append(feed)
        persistSavedFeeds()
    }

    /// Removes a spell feed from the saved list.
    func removeFeed(id: String) {
        savedFeeds.removeAll { $0.id == id }
        if selectedTabId == id {
            selectedTabId = "following"
            persistSelectedTab()
        }
        persistSavedFeeds()
    }

    /// Moves a spell feed in the saved list (for reordering).
    func moveFeed(from source: IndexSet, to destination: Int) {
        savedFeeds.move(fromOffsets: source, toOffset: destination)
        persistSavedFeeds()
    }

    /// Renames a spell feed.
    func renameFeed(id: String, newName: String) {
        guard let index = savedFeeds.firstIndex(where: { $0.id == id }) else { return }
        let old = savedFeeds[index]
        savedFeeds[index] = SavedSpellFeed(id: old.id, name: newName, spellEventJSON: old.spellEventJSON)
        persistSavedFeeds()
    }

    /// Selects a tab by its ID.
    func selectTab(_ tabId: String) {
        selectedTabId = tabId
        persistSelectedTab()
    }

    /// Seeds starter feeds on first launch (no-op if feeds already exist).
    func seedStarterFeedsIfNeeded(starterFeeds: [SavedSpellFeed]) {
        let hasBeenSeeded = userDefaults.bool(forKey: "spell_starter_seeded")
        guard !hasBeenSeeded else { return }

        for feed in starterFeeds {
            addFeed(feed)
        }
        userDefaults.set(true, forKey: "spell_starter_seeded")
    }

    // MARK: - Persistence

    private func loadSavedFeeds() {
        guard let data = userDefaults.data(forKey: Self.savedFeedsKey) else { return }
        if let decoded = try? JSONDecoder().decode([SavedSpellFeed].self, from: data) {
            savedFeeds = decoded
        }
    }

    private func persistSavedFeeds() {
        if let data = try? JSONEncoder().encode(savedFeeds) {
            userDefaults.set(data, forKey: Self.savedFeedsKey)
        }
    }

    private func loadSelectedTab() {
        if let tabId = userDefaults.string(forKey: Self.selectedTabKey) {
            selectedTabId = tabId
        }
    }

    private func persistSelectedTab() {
        userDefaults.set(selectedTabId, forKey: Self.selectedTabKey)
    }
}
