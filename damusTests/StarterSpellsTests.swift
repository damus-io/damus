//
//  StarterSpellsTests.swift
//  damusTests
//
//  Tests for StarterSpells and SpellDiscoveryModel.
//

import XCTest
@testable import damus

final class StarterSpellsTests: XCTestCase {

    // MARK: - StarterSpells

    func test_starter_feeds_are_not_empty() {
        XCTAssertFalse(StarterSpells.feeds.isEmpty)
    }

    func test_starter_feeds_have_unique_ids() {
        let ids = StarterSpells.feeds.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Starter feed IDs must be unique")
    }

    func test_starter_feeds_have_names() {
        for feed in StarterSpells.feeds {
            XCTAssertFalse(feed.name.isEmpty, "Feed \(feed.id) should have a name")
        }
    }

    func test_starter_feeds_parse_into_spells() {
        for feed in StarterSpells.feeds {
            let json = feed.spellEventJSON
            let parsedNote = NostrEvent.owned_from_json(json: json)
            XCTAssertNotNil(parsedNote, "JSON should parse back to NdbNote for '\(feed.name)'")

            if let parsedNote {
                let spell = SpellEvent.parse(from: parsedNote)
                XCTAssertNotNil(spell, "Starter feed '\(feed.name)' (id: \(feed.id)) should parse")
            }
        }
    }

    func test_global_notes_spell_has_kind_1() {
        let globalFeed = StarterSpells.feeds.first { $0.id == "starter_global_notes" }
        XCTAssertNotNil(globalFeed)

        let spell = globalFeed!.parseSpell()
        XCTAssertNotNil(spell)
        XCTAssertTrue(spell!.kinds.contains(1))
    }

    func test_images_spell_has_kind_20() {
        let imagesFeed = StarterSpells.feeds.first { $0.id == "starter_images" }
        XCTAssertNotNil(imagesFeed)

        let spell = imagesFeed!.parseSpell()
        XCTAssertNotNil(spell)
        XCTAssertTrue(spell!.kinds.contains(20), "Images feed should use kind:20 (NIP-68 picture events)")
        XCTAssertNil(spell!.search, "Images feed should not use search filter")
    }

    // MARK: - FeedTabStore seeding integration

    @MainActor
    func test_seed_starter_feeds_integrates_with_store() {
        let defaults = UserDefaults(suiteName: "StarterSpellsTests_\(UUID().uuidString)")!
        let store = FeedTabStore(userDefaults: defaults)

        store.seedStarterFeedsIfNeeded(starterFeeds: StarterSpells.feeds)

        XCTAssertEqual(store.savedFeeds.count, StarterSpells.feeds.count)
        XCTAssertEqual(store.tabs.count, StarterSpells.feeds.count + 1) // +1 for Following
    }

    @MainActor
    func test_seed_does_not_duplicate_on_second_call() {
        let defaults = UserDefaults(suiteName: "StarterSpellsTests_\(UUID().uuidString)")!
        let store = FeedTabStore(userDefaults: defaults)

        store.seedStarterFeedsIfNeeded(starterFeeds: StarterSpells.feeds)
        store.seedStarterFeedsIfNeeded(starterFeeds: StarterSpells.feeds)

        XCTAssertEqual(store.savedFeeds.count, StarterSpells.feeds.count)
    }

    // MARK: - DiscoveredSpell

    func test_discovered_spell_to_saved_feed() {
        let ev = NostrEvent(
            content: "Test spell",
            keypair: test_keypair,
            kind: 777,
            tags: [["cmd", "REQ"], ["k", "1"]]
        )!

        let spell = SpellEvent.parse(from: ev)!
        let json = event_to_json(ev: ev)
        let discovered = DiscoveredSpell(
            noteId: ev.id,
            spell: spell,
            eventJSON: json,
            authorPubkey: ev.pubkey
        )

        let saved = discovered.toSavedFeed()
        XCTAssertEqual(saved.id, ev.id.hex())
        XCTAssertEqual(saved.name, "Custom Feed")
        XCTAssertFalse(saved.spellEventJSON.isEmpty)

        // Round-trip: saved feed parses back to spell
        let parsed = saved.parseSpell()
        XCTAssertNotNil(parsed)
        XCTAssertTrue(parsed!.kinds.contains(1))
    }

    func test_discovered_spell_display_name() {
        let ev = NostrEvent(
            content: "",
            keypair: test_keypair,
            kind: 777,
            tags: [["cmd", "REQ"], ["k", "1"], ["name", "My Feed"]]
        )!

        let spell = SpellEvent.parse(from: ev)!
        let discovered = DiscoveredSpell(
            noteId: ev.id,
            spell: spell,
            eventJSON: "{}",
            authorPubkey: ev.pubkey
        )

        XCTAssertEqual(discovered.displayName, "My Feed")
    }
}
