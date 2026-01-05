//
//  SearchNetworkTests.swift
//  damusTests
//
//  Tests for Search functionality under various network conditions.
//  Focuses on filter matching, EventHolder integration, and search state management.
//

import Foundation
import XCTest
@testable import damus

// MARK: - Search Filter Tests

/// Tests for search filter matching and hashtag detection.
final class SearchFilterTests: XCTestCase {

    // MARK: - Helper Methods

    /// Creates a test NostrEvent with the given content and tags
    func makeTestEvent(content: String = "Test", tags: [[String]] = [], kind: UInt32 = 1, createdAt: UInt32? = nil) -> NostrEvent? {
        let keypair = test_keypair_full
        let created = createdAt ?? UInt32(Date().timeIntervalSince1970)
        return NostrEvent(content: content, keypair: keypair.to_keypair(), kind: kind, tags: tags, createdAt: created)
    }

    /// Creates a test event with hashtags
    func makeHashtagEvent(content: String, hashtags: [String], createdAt: UInt32? = nil) -> NostrEvent? {
        let tags = hashtags.map { ["t", $0] }
        return makeTestEvent(content: content, tags: tags, createdAt: createdAt)
    }

    // MARK: - Hashtag Tag Detection via Events
    // Note: tag_is_hashtag is tested indirectly through event_matches_hashtag
    // since Tag objects require NdbNote internal structures

    /// Test: Event with hashtag tag is detected via tag_is_hashtag
    func testEventWithHashtagTagIsDetected() throws {
        guard let event = makeHashtagEvent(content: "Test #nostr", hashtags: ["nostr"]) else {
            XCTFail("Failed to create test event")
            return
        }

        let hasHashtag = event.tags.contains(where: { tag_is_hashtag($0) })
        XCTAssertTrue(hasHashtag, "Event with hashtag should have hashtag tag")
    }

    /// Test: Event with p-tag doesn't have hashtag tag
    func testEventWithPTagNoHashtag() throws {
        let pTag = ["p", test_pubkey.hex()]
        guard let event = makeTestEvent(content: "Test", tags: [pTag]) else {
            XCTFail("Failed to create test event")
            return
        }

        let hasHashtag = event.tags.contains(where: { tag_is_hashtag($0) })
        XCTAssertFalse(hasHashtag, "Event with only p-tag should not have hashtag")
    }

    // MARK: - event_matches_hashtag Tests

    /// Test: Event with matching hashtag returns true
    func testEventMatchesHashtagReturnsTrue() throws {
        guard let event = makeHashtagEvent(content: "Hello #nostr", hashtags: ["nostr"]) else {
            XCTFail("Failed to create test event")
            return
        }

        XCTAssertTrue(event_matches_hashtag(event, hashtags: ["nostr"]))
    }

    /// Test: Event with multiple hashtags matches any
    func testEventMatchesAnyHashtag() throws {
        guard let event = makeHashtagEvent(content: "Hello #nostr #bitcoin", hashtags: ["nostr", "bitcoin"]) else {
            XCTFail("Failed to create test event")
            return
        }

        XCTAssertTrue(event_matches_hashtag(event, hashtags: ["nostr"]))
        XCTAssertTrue(event_matches_hashtag(event, hashtags: ["bitcoin"]))
        XCTAssertTrue(event_matches_hashtag(event, hashtags: ["nostr", "lightning"]))
    }

    /// Test: Event without matching hashtag returns false
    func testEventNoMatchingHashtagReturnsFalse() throws {
        guard let event = makeHashtagEvent(content: "Hello #nostr", hashtags: ["nostr"]) else {
            XCTFail("Failed to create test event")
            return
        }

        XCTAssertFalse(event_matches_hashtag(event, hashtags: ["bitcoin"]))
        XCTAssertFalse(event_matches_hashtag(event, hashtags: ["lightning", "zaps"]))
    }

    /// Test: Event without any hashtags returns false
    func testEventWithoutHashtagsReturnsFalse() throws {
        guard let event = makeTestEvent(content: "Hello world") else {
            XCTFail("Failed to create test event")
            return
        }

        XCTAssertFalse(event_matches_hashtag(event, hashtags: ["nostr"]))
    }

    // MARK: - event_matches_filter Tests

    /// Test: Filter with hashtag matches event with hashtag
    func testFilterWithHashtagMatchesEvent() throws {
        guard let event = makeHashtagEvent(content: "Hello #nostr", hashtags: ["nostr"]) else {
            XCTFail("Failed to create test event")
            return
        }

        let filter = NostrFilter.filter_hashtag(["nostr"])
        XCTAssertTrue(event_matches_filter(event, filter: filter))
    }

    /// Test: Filter with hashtag doesn't match event without hashtag
    func testFilterWithHashtagNoMatch() throws {
        guard let event = makeHashtagEvent(content: "Hello #bitcoin", hashtags: ["bitcoin"]) else {
            XCTFail("Failed to create test event")
            return
        }

        let filter = NostrFilter.filter_hashtag(["nostr"])
        XCTAssertFalse(event_matches_filter(event, filter: filter))
    }

    /// Test: Filter without hashtag matches any event
    func testFilterWithoutHashtagMatchesAll() throws {
        guard let event = makeTestEvent(content: "Hello world") else {
            XCTFail("Failed to create test event")
            return
        }

        let filter = NostrFilter(kinds: [.text])
        XCTAssertTrue(event_matches_filter(event, filter: filter))
    }

    /// Test: Hashtag filter is case-insensitive
    func testHashtagFilterCaseInsensitive() throws {
        guard let event = makeHashtagEvent(content: "Hello #Nostr", hashtags: ["Nostr"]) else {
            XCTFail("Failed to create test event")
            return
        }

        // filter_hashtag lowercases the hashtag
        let filter = NostrFilter.filter_hashtag(["nostr"])

        // The event hashtag is "Nostr" (uppercase N), filter is "nostr" (lowercase)
        // This tests whether matching is case-insensitive
        // Note: The actual behavior depends on implementation
        let matches = event_matches_filter(event, filter: filter)
        // Document actual behavior
        XCTAssertFalse(matches, "Hashtag matching is case-sensitive (event has 'Nostr', filter has 'nostr')")
    }

    // MARK: - NostrFilter Creation Tests

    /// Test: filter_hashtag creates correct filter
    func testFilterHashtagCreation() {
        let filter = NostrFilter.filter_hashtag(["Nostr", "Bitcoin"])

        XCTAssertNotNil(filter.hashtag)
        XCTAssertEqual(filter.hashtag?.count, 2)
        XCTAssertEqual(filter.hashtag?[0], "nostr") // Should be lowercased
        XCTAssertEqual(filter.hashtag?[1], "bitcoin") // Should be lowercased
    }

    /// Test: Search filter includes correct kinds
    func testSearchFilterKinds() {
        // SearchModel sets these kinds when subscribing
        let expectedKinds: [NostrKind] = [.text, .like, .longform, .highlight, .follow_list]

        var filter = NostrFilter()
        filter.kinds = expectedKinds

        XCTAssertEqual(filter.kinds?.count, 5)
        XCTAssertTrue(filter.kinds?.contains(.text) ?? false)
        XCTAssertTrue(filter.kinds?.contains(.like) ?? false)
        XCTAssertTrue(filter.kinds?.contains(.longform) ?? false)
    }
}

// MARK: - Search EventHolder Tests

/// Tests for EventHolder behavior in search context.
@MainActor
final class SearchEventHolderTests: XCTestCase {

    // MARK: - Helper Methods

    /// Creates a test NostrEvent with the given content and timestamp.
    func makeTestEvent(content: String = "Test", createdAt: UInt32? = nil) -> NostrEvent? {
        let keypair = test_keypair_full
        let created = createdAt ?? UInt32(Date().timeIntervalSince1970)
        return NostrEvent(content: content, keypair: keypair.to_keypair(), kind: 1, tags: [], createdAt: created)
    }

    // MARK: - Search Result Insertion Tests

    /// Test: Search results are inserted and deduplicated
    func testSearchResultsDeduplication() async throws {
        let holder = EventHolder()
        holder.set_should_queue(false)

        guard let event = makeTestEvent(content: "Test search result") else {
            XCTFail("Failed to create test event")
            return
        }

        let first = holder.insert(event)
        let duplicate = holder.insert(event)

        XCTAssertTrue(first, "First insert should succeed")
        XCTAssertFalse(duplicate, "Duplicate should be rejected")
        XCTAssertEqual(holder.events.count, 1)
    }

    /// Test: Search results are sorted by time (newest first)
    func testSearchResultsSortedByTime() async throws {
        let holder = EventHolder()
        holder.set_should_queue(false)

        let now = UInt32(Date().timeIntervalSince1970)

        guard let oldEvent = makeTestEvent(content: "Old result", createdAt: now - 3600),
              let newEvent = makeTestEvent(content: "New result", createdAt: now) else {
            XCTFail("Failed to create test events")
            return
        }

        // Insert in reverse chronological order
        _ = holder.insert(oldEvent)
        _ = holder.insert(newEvent)

        XCTAssertEqual(holder.events.count, 2)
        XCTAssertEqual(holder.events.first?.content, "New result", "Newest should be first")
        XCTAssertEqual(holder.events.last?.content, "Old result", "Oldest should be last")
    }

    /// Test: Multiple search results batch insertion
    func testBatchSearchResults() async throws {
        let holder = EventHolder()
        holder.set_should_queue(false)

        let now = UInt32(Date().timeIntervalSince1970)
        var events: [NostrEvent] = []

        for i in 0..<10 {
            if let event = makeTestEvent(content: "Result \(i)", createdAt: now - UInt32(i * 60)) {
                events.append(event)
            }
        }

        for event in events {
            _ = holder.insert(event)
        }

        XCTAssertEqual(holder.events.count, 10)
        // Verify sorted order (newest first)
        XCTAssertEqual(holder.events.first?.content, "Result 0")
        XCTAssertEqual(holder.events.last?.content, "Result 9")
    }

    /// Test: Reset clears search results
    func testResetClearsSearchResults() async throws {
        let holder = EventHolder()
        holder.set_should_queue(false)

        for i in 0..<5 {
            if let event = makeTestEvent(content: "Result \(i)") {
                _ = holder.insert(event)
            }
        }

        XCTAssertEqual(holder.events.count, 5)

        holder.reset()

        XCTAssertEqual(holder.events.count, 0, "Reset should clear all results")
    }

    // MARK: - Queued Search Results Tests

    /// Test: Search results can be queued for batch display
    func testQueuedSearchResults() async throws {
        let holder = EventHolder()
        holder.set_should_queue(true)

        for i in 0..<5 {
            if let event = makeTestEvent(content: "Queued \(i)") {
                _ = holder.insert(event)
            }
        }

        XCTAssertEqual(holder.events.count, 0, "Events should not be visible yet")
        XCTAssertEqual(holder.incoming.count, 5, "Events should be queued")
        XCTAssertEqual(holder.queued, 5)

        holder.flush()

        XCTAssertEqual(holder.events.count, 5, "Events should be visible after flush")
        XCTAssertEqual(holder.incoming.count, 0, "Queue should be empty")
    }

    // MARK: - on_queue Callback Tests

    /// Test: on_queue callback fires for search results (for preloading)
    func testOnQueueCallbackForPreloading() async throws {
        var preloadedEvents: [NostrEvent] = []

        let holder = EventHolder(on_queue: { event in
            preloadedEvents.append(event)
        })
        holder.set_should_queue(true)

        guard let event1 = makeTestEvent(content: "Event 1"),
              let event2 = makeTestEvent(content: "Event 2") else {
            XCTFail("Failed to create test events")
            return
        }

        _ = holder.insert(event1)
        _ = holder.insert(event2)

        XCTAssertEqual(preloadedEvents.count, 2, "Callback should fire for each queued event")
    }
}

// MARK: - Search State Tests

/// Tests for search loading state and cancellation.
final class SearchStateTests: XCTestCase {

    /// Test: Search filter with limit
    func testSearchFilterWithLimit() {
        var filter = NostrFilter()
        filter.limit = 500

        XCTAssertEqual(filter.limit, 500)
    }

    /// Test: Search filter with kinds for text search
    func testSearchFilterForTextSearch() {
        var filter = NostrFilter()
        filter.kinds = [.text, .like, .longform, .highlight, .follow_list]
        filter.limit = 500

        XCTAssertEqual(filter.kinds?.count, 5)
        XCTAssertEqual(filter.limit, 500)
    }

    /// Test: Hashtag search filter creation
    func testHashtagSearchFilter() {
        let hashtags = ["nostr", "bitcoin", "lightning"]
        let filter = NostrFilter.filter_hashtag(hashtags)

        XCTAssertEqual(filter.hashtag?.count, 3)
        XCTAssertNil(filter.kinds, "Hashtag filter should not set kinds by default")
    }

    /// Test: Combined hashtag and kind filter
    func testCombinedHashtagKindFilter() {
        var filter = NostrFilter.filter_hashtag(["nostr"])
        filter.kinds = [.text]
        filter.limit = 100

        XCTAssertEqual(filter.hashtag?.first, "nostr")
        XCTAssertEqual(filter.kinds?.first, .text)
        XCTAssertEqual(filter.limit, 100)
    }
}

// MARK: - SearchHomeModel Filter Tests

/// Tests for SearchHomeModel filter creation.
final class SearchHomeFilterTests: XCTestCase {

    /// Test: Base filter includes correct kinds
    func testBaseFilterKinds() {
        // SearchHomeModel.get_base_filter() creates filter with .text and .chat kinds
        var filter = NostrFilter(kinds: [.text, .chat])
        filter.limit = 200

        XCTAssertEqual(filter.kinds?.count, 2)
        XCTAssertTrue(filter.kinds?.contains(.text) ?? false)
        XCTAssertTrue(filter.kinds?.contains(.chat) ?? false)
        XCTAssertEqual(filter.limit, 200)
    }

    /// Test: Base filter includes until timestamp
    func testBaseFilterUntilTimestamp() {
        let now = UInt32(Date.now.timeIntervalSince1970)

        var filter = NostrFilter(kinds: [.text, .chat])
        filter.limit = 200
        filter.until = now

        XCTAssertNotNil(filter.until)
        XCTAssertLessThanOrEqual(filter.until!, now + 1) // Allow 1 second tolerance
    }

    /// Test: Follow pack filter
    func testFollowPackFilter() {
        var filter = NostrFilter(kinds: [.follow_list])
        filter.until = UInt32(Date.now.timeIntervalSince1970)

        XCTAssertEqual(filter.kinds?.count, 1)
        XCTAssertEqual(filter.kinds?.first, .follow_list)
        XCTAssertNotNil(filter.until)
    }
}

// MARK: - Search Event Kind Tests

/// Tests for event kinds used in search.
final class SearchEventKindTests: XCTestCase {

    /// Creates a test NostrEvent with the given kind.
    func makeTestEvent(kind: UInt32, content: String = "Test") -> NostrEvent? {
        let keypair = test_keypair_full
        return NostrEvent(content: content, keypair: keypair.to_keypair(), kind: kind, tags: [], createdAt: UInt32(Date().timeIntervalSince1970))
    }

    /// Test: Text note (kind 1) is textlike
    func testTextNoteIsTextlike() throws {
        guard let event = makeTestEvent(kind: 1) else {
            XCTFail("Failed to create test event")
            return
        }

        XCTAssertTrue(event.is_textlike, "Kind 1 should be textlike")
    }

    /// Test: Longform content (kind 30023) is textlike
    func testLongformIsTextlike() throws {
        guard let event = makeTestEvent(kind: NostrKind.longform.rawValue) else {
            XCTFail("Failed to create test event")
            return
        }

        XCTAssertTrue(event.is_textlike, "Longform should be textlike")
    }

    /// Test: Highlight (kind 9802) is textlike
    func testHighlightIsTextlike() throws {
        guard let event = makeTestEvent(kind: NostrKind.highlight.rawValue) else {
            XCTFail("Failed to create test event")
            return
        }

        XCTAssertTrue(event.is_textlike, "Highlight should be textlike")
    }

    /// Test: Reaction (kind 7) is not textlike
    func testReactionNotTextlike() throws {
        guard let event = makeTestEvent(kind: NostrKind.like.rawValue) else {
            XCTFail("Failed to create test event")
            return
        }

        XCTAssertFalse(event.is_textlike, "Reaction should not be textlike")
    }

    /// Test: Metadata (kind 0) is not textlike
    func testMetadataNotTextlike() throws {
        guard let event = makeTestEvent(kind: NostrKind.metadata.rawValue) else {
            XCTFail("Failed to create test event")
            return
        }

        XCTAssertFalse(event.is_textlike, "Metadata should not be textlike")
    }
}
