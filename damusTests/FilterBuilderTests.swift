//
//  FilterBuilderTests.swift
//  damusTests
//
//  Tests for FilterBuilderModel and tag generation.
//

import XCTest
@testable import damus

@MainActor
final class FilterBuilderTests: XCTestCase {

    // MARK: - Validation

    func test_empty_name_is_invalid() {
        let model = FilterBuilderModel()
        model.feedName = ""
        XCTAssertFalse(model.isValid)
    }

    func test_whitespace_name_is_invalid() {
        let model = FilterBuilderModel()
        model.feedName = "   "
        XCTAssertFalse(model.isValid)
    }

    func test_valid_name_with_kinds_is_valid() {
        let model = FilterBuilderModel()
        model.feedName = "My Feed"
        model.selectedKinds = [1]
        XCTAssertTrue(model.isValid)
    }

    func test_no_kinds_selected_is_invalid() {
        let model = FilterBuilderModel()
        model.feedName = "My Feed"
        model.selectedKinds = []
        XCTAssertFalse(model.isValid)
    }

    // MARK: - Tag Building

    func test_builds_cmd_tag() {
        let model = FilterBuilderModel()
        model.feedName = "Test"
        let tags = model.buildTags()
        XCTAssertTrue(tags.contains(["cmd", "REQ"]))
    }

    func test_builds_kind_tags() {
        let model = FilterBuilderModel()
        model.feedName = "Test"
        model.selectedKinds = [1, 7]
        let tags = model.buildTags()
        XCTAssertTrue(tags.contains(["k", "1"]))
        XCTAssertTrue(tags.contains(["k", "7"]))
    }

    func test_kinds_are_sorted() {
        let model = FilterBuilderModel()
        model.feedName = "Test"
        model.selectedKinds = [9735, 1, 30023]
        let tags = model.buildTags()

        let kindTags = tags.filter { $0.first == "k" }
        let kindValues = kindTags.map { $0[1] }
        XCTAssertEqual(kindValues, ["1", "9735", "30023"])
    }

    func test_custom_kind_added() {
        let model = FilterBuilderModel()
        model.feedName = "Test"
        model.selectedKinds = [1]
        model.customKindText = "42"
        let tags = model.buildTags()
        XCTAssertTrue(tags.contains(["k", "42"]))
    }

    func test_custom_kind_not_duplicated() {
        let model = FilterBuilderModel()
        model.feedName = "Test"
        model.selectedKinds = [1]
        model.customKindText = "1"
        let tags = model.buildTags()

        let kindTags = tags.filter { $0.first == "k" }
        XCTAssertEqual(kindTags.count, 1)
    }

    func test_author_scope_anyone_no_tag() {
        let model = FilterBuilderModel()
        model.feedName = "Test"
        model.authorScope = .anyone
        let tags = model.buildTags()
        XCTAssertFalse(tags.contains { $0.first == "authors" })
    }

    func test_author_scope_me() {
        let model = FilterBuilderModel()
        model.feedName = "Test"
        model.authorScope = .me
        let tags = model.buildTags()
        XCTAssertTrue(tags.contains(["authors", "$me"]))
    }

    func test_author_scope_contacts() {
        let model = FilterBuilderModel()
        model.feedName = "Test"
        model.authorScope = .contacts
        let tags = model.buildTags()
        XCTAssertTrue(tags.contains(["authors", "$contacts"]))
    }

    func test_since_preset() {
        let model = FilterBuilderModel()
        model.feedName = "Test"
        model.sincePreset = "7d"
        let tags = model.buildTags()
        XCTAssertTrue(tags.contains(["since", "-7d"]))
    }

    func test_no_since_when_empty() {
        let model = FilterBuilderModel()
        model.feedName = "Test"
        model.sincePreset = ""
        let tags = model.buildTags()
        XCTAssertFalse(tags.contains { $0.first == "since" })
    }

    func test_search_text() {
        let model = FilterBuilderModel()
        model.feedName = "Test"
        model.searchText = "bitcoin"
        let tags = model.buildTags()
        XCTAssertTrue(tags.contains(["search", "bitcoin"]))
    }

    func test_empty_search_omitted() {
        let model = FilterBuilderModel()
        model.feedName = "Test"
        model.searchText = "   "
        let tags = model.buildTags()
        XCTAssertFalse(tags.contains { $0.first == "search" })
    }

    func test_hashtag_filter() {
        let model = FilterBuilderModel()
        model.feedName = "Test"
        model.hashtagText = "nostr"
        let tags = model.buildTags()
        XCTAssertTrue(tags.contains(["tag", "t", "nostr"]))
    }

    func test_hashtag_strips_hash_prefix() {
        let model = FilterBuilderModel()
        model.feedName = "Test"
        model.hashtagText = "#bitcoin"
        let tags = model.buildTags()
        XCTAssertTrue(tags.contains(["tag", "t", "bitcoin"]))
    }

    func test_limit_tag() {
        let model = FilterBuilderModel()
        model.feedName = "Test"
        model.limit = 50
        let tags = model.buildTags()
        XCTAssertTrue(tags.contains(["limit", "50"]))
    }

    func test_name_tag_included() {
        let model = FilterBuilderModel()
        model.feedName = "My Cool Feed"
        let tags = model.buildTags()
        XCTAssertTrue(tags.contains(["name", "My Cool Feed"]))
    }

    // MARK: - Build Saved Feed

    func test_build_saved_feed_round_trip() {
        let model = FilterBuilderModel()
        model.feedName = "Test Feed"
        model.feedDescription = "A test"
        model.selectedKinds = [1]
        model.sincePreset = "24h"

        let saved = model.buildSavedFeed()
        XCTAssertNotNil(saved)
        XCTAssertEqual(saved!.name, "Test Feed")
        XCTAssertFalse(saved!.spellEventJSON.isEmpty)

        // Round-trip: parse the saved spell
        let spell = saved!.parseSpell()
        XCTAssertNotNil(spell)
        XCTAssertTrue(spell!.kinds.contains(1))
        XCTAssertEqual(spell!.name, "Test Feed")
    }

    func test_build_saved_feed_returns_nil_when_invalid() {
        let model = FilterBuilderModel()
        model.feedName = ""
        XCTAssertNil(model.buildSavedFeed())
    }

    func test_build_saved_feed_with_all_options() {
        let model = FilterBuilderModel()
        model.feedName = "Full"
        model.feedDescription = "All options"
        model.selectedKinds = [1, 7]
        model.authorScope = .contacts
        model.sincePreset = "7d"
        model.searchText = "test"
        model.hashtagText = "nostr"
        model.limit = 50

        let saved = model.buildSavedFeed()
        XCTAssertNotNil(saved)

        let spell = saved!.parseSpell()
        XCTAssertNotNil(spell)
        XCTAssertTrue(spell!.kinds.contains(1))
        XCTAssertTrue(spell!.kinds.contains(7))
        XCTAssertEqual(spell!.search, "test")
        XCTAssertEqual(spell!.name, "Full")
    }

    // MARK: - Presets

    func test_kind_presets_not_empty() {
        XCTAssertFalse(KindPreset.presets.isEmpty)
    }

    func test_kind_presets_unique() {
        let kinds = KindPreset.presets.map(\.kind)
        XCTAssertEqual(kinds.count, Set(kinds).count)
    }

    func test_time_presets_not_empty() {
        XCTAssertFalse(TimePreset.presets.isEmpty)
    }

    func test_time_presets_unique() {
        let tags = TimePreset.presets.map(\.tag)
        XCTAssertEqual(tags.count, Set(tags).count)
    }
}
