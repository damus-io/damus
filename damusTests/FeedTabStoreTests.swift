//
//  FeedTabStoreTests.swift
//  damusTests
//
//  Tests for FeedTabStore persistence and tab management.
//

import XCTest
@testable import damus

@MainActor
final class FeedTabStoreTests: XCTestCase {

    private func makeStore() -> FeedTabStore {
        let defaults = UserDefaults(suiteName: "FeedTabStoreTests_\(UUID().uuidString)")!
        return FeedTabStore(userDefaults: defaults)
    }

    private func makeSavedFeed(id: String = "test1", name: String = "Bitcoin") -> SavedSpellFeed {
        SavedSpellFeed(id: id, name: name, spellEventJSON: "{}")
    }

    // MARK: - Initial state

    func test_initial_state_has_only_following() {
        let store = makeStore()
        XCTAssertEqual(store.tabs.count, 1)
        XCTAssertEqual(store.tabs.first?.id, "following")
        XCTAssertEqual(store.selectedTabId, "following")
        XCTAssertEqual(store.selectedTab, .following)
    }

    // MARK: - Adding feeds

    func test_add_feed_appends_tab() {
        let store = makeStore()
        let feed = makeSavedFeed()
        store.addFeed(feed)

        XCTAssertEqual(store.tabs.count, 2)
        XCTAssertEqual(store.tabs[1].id, "test1")
        XCTAssertEqual(store.tabs[1].label, "Bitcoin")
    }

    func test_add_duplicate_feed_is_noop() {
        let store = makeStore()
        let feed = makeSavedFeed()
        store.addFeed(feed)
        store.addFeed(feed)

        XCTAssertEqual(store.savedFeeds.count, 1)
    }

    func test_add_multiple_feeds() {
        let store = makeStore()
        store.addFeed(makeSavedFeed(id: "a", name: "Alpha"))
        store.addFeed(makeSavedFeed(id: "b", name: "Beta"))
        store.addFeed(makeSavedFeed(id: "c", name: "Gamma"))

        XCTAssertEqual(store.tabs.count, 4) // following + 3
        XCTAssertEqual(store.tabs.map(\.id), ["following", "a", "b", "c"])
    }

    // MARK: - Removing feeds

    func test_remove_feed() {
        let store = makeStore()
        store.addFeed(makeSavedFeed(id: "a", name: "Alpha"))
        store.addFeed(makeSavedFeed(id: "b", name: "Beta"))

        store.removeFeed(id: "a")

        XCTAssertEqual(store.savedFeeds.count, 1)
        XCTAssertEqual(store.savedFeeds.first?.id, "b")
    }

    func test_remove_selected_feed_resets_to_following() {
        let store = makeStore()
        store.addFeed(makeSavedFeed(id: "spell1"))
        store.selectTab("spell1")
        XCTAssertEqual(store.selectedTabId, "spell1")

        store.removeFeed(id: "spell1")
        XCTAssertEqual(store.selectedTabId, "following")
    }

    // MARK: - Tab selection

    func test_select_tab() {
        let store = makeStore()
        store.addFeed(makeSavedFeed(id: "spell1"))
        store.selectTab("spell1")

        XCTAssertEqual(store.selectedTabId, "spell1")
        if case .spell(let saved) = store.selectedTab {
            XCTAssertEqual(saved.id, "spell1")
        } else {
            XCTFail("Expected .spell tab")
        }
    }

    func test_select_nonexistent_tab_falls_back_to_following() {
        let store = makeStore()
        store.selectTab("nonexistent")

        // selectedTabId is set but selectedTab falls back
        XCTAssertEqual(store.selectedTab, .following)
    }

    // MARK: - Reordering

    func test_move_feed() {
        let store = makeStore()
        store.addFeed(makeSavedFeed(id: "a", name: "Alpha"))
        store.addFeed(makeSavedFeed(id: "b", name: "Beta"))
        store.addFeed(makeSavedFeed(id: "c", name: "Gamma"))

        // Move "a" to position after "b"
        store.moveFeed(from: IndexSet(integer: 0), to: 2)

        XCTAssertEqual(store.savedFeeds.map(\.id), ["b", "a", "c"])
    }

    // MARK: - Persistence

    func test_persistence_round_trip() {
        let suiteName = "FeedTabStoreTests_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        // Write
        let store1 = FeedTabStore(userDefaults: defaults)
        store1.addFeed(makeSavedFeed(id: "x", name: "Nostr"))
        store1.selectTab("x")

        // Read
        let store2 = FeedTabStore(userDefaults: defaults)
        XCTAssertEqual(store2.savedFeeds.count, 1)
        XCTAssertEqual(store2.savedFeeds.first?.name, "Nostr")
        XCTAssertEqual(store2.selectedTabId, "x")
    }

    // MARK: - Starter feeds

    func test_seed_starter_feeds_adds_on_first_call() {
        let store = makeStore()
        let starters = [
            makeSavedFeed(id: "s1", name: "Starter 1"),
            makeSavedFeed(id: "s2", name: "Starter 2")
        ]

        store.seedStarterFeedsIfNeeded(starterFeeds: starters)

        XCTAssertEqual(store.savedFeeds.count, 2)
    }

    func test_seed_starter_feeds_noop_on_second_call() {
        let store = makeStore()
        let starters = [makeSavedFeed(id: "s1", name: "Starter")]

        store.seedStarterFeedsIfNeeded(starterFeeds: starters)
        store.seedStarterFeedsIfNeeded(starterFeeds: [makeSavedFeed(id: "s2", name: "New")])

        XCTAssertEqual(store.savedFeeds.count, 1)
        XCTAssertEqual(store.savedFeeds.first?.id, "s1")
    }

    // MARK: - Renaming

    func test_rename_feed() {
        let store = makeStore()
        store.addFeed(makeSavedFeed(id: "a", name: "Alpha"))
        store.renameFeed(id: "a", newName: "Renamed")

        XCTAssertEqual(store.savedFeeds.first?.name, "Renamed")
        XCTAssertEqual(store.savedFeeds.first?.id, "a")
    }

    func test_rename_preserves_json() {
        let store = makeStore()
        let feed = SavedSpellFeed(id: "a", name: "Alpha", spellEventJSON: "{\"test\":1}")
        store.addFeed(feed)
        store.renameFeed(id: "a", newName: "Beta")

        XCTAssertEqual(store.savedFeeds.first?.spellEventJSON, "{\"test\":1}")
    }

    func test_rename_nonexistent_feed_is_noop() {
        let store = makeStore()
        store.addFeed(makeSavedFeed(id: "a", name: "Alpha"))
        store.renameFeed(id: "nonexistent", newName: "Whatever")

        XCTAssertEqual(store.savedFeeds.first?.name, "Alpha")
    }

    func test_rename_persists() {
        let suiteName = "FeedTabStoreTests_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!

        let store1 = FeedTabStore(userDefaults: defaults)
        store1.addFeed(makeSavedFeed(id: "a", name: "Alpha"))
        store1.renameFeed(id: "a", newName: "Beta")

        let store2 = FeedTabStore(userDefaults: defaults)
        XCTAssertEqual(store2.savedFeeds.first?.name, "Beta")
    }

    // MARK: - FeedTab model

    func test_feed_tab_following_label() {
        XCTAssertEqual(FeedTab.following.label, "Following")
        XCTAssertEqual(FeedTab.following.id, "following")
    }

    func test_feed_tab_spell_label() {
        let tab = FeedTab.spell(makeSavedFeed(id: "z", name: "Zaps"))
        XCTAssertEqual(tab.label, "Zaps")
        XCTAssertEqual(tab.id, "z")
    }

    func test_feed_tab_equatable() {
        let feed = makeSavedFeed(id: "x", name: "Test")
        XCTAssertEqual(FeedTab.following, FeedTab.following)
        XCTAssertEqual(FeedTab.spell(feed), FeedTab.spell(feed))
        XCTAssertNotEqual(FeedTab.following, FeedTab.spell(feed))
    }
}
