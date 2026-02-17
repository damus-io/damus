//
//  GroupedTimelineGrouperTests.swift
//  damusTests
//
//  Created by alltheseas on 2025-12-07.
//

import XCTest
@testable import damus

final class GroupedTimelineGrouperTests: XCTestCase {

    // MARK: - Helpers

    private let now = Date()

    private func makeEvent(
        content: String = "Hello, this is a test note with enough words",
        keypair: Keypair = test_keypair,
        secondsAgo: UInt32 = 100,
        tags: [[String]] = []
    ) -> NostrEvent {
        NostrEvent(
            content: content,
            keypair: keypair,
            tags: tags,
            createdAt: UInt32(now.timeIntervalSince1970) - secondsAgo
        )!
    }

    private func defaultValues(
        includeReplies: Bool = false,
        hideShortNotes: Bool = false,
        filteredWords: String = "",
        maxNotesPerUser: Int? = nil
    ) -> GroupedFilterValues {
        GroupedFilterValues(
            timeRangeSeconds: 24 * 60 * 60,
            includeReplies: includeReplies,
            hideShortNotes: hideShortNotes,
            filteredWords: filteredWords,
            maxNotesPerUser: maxNotesPerUser
        )
    }

    // MARK: - Empty Input

    func testEmptyEventsReturnsEmptyGroups() {
        let groups = GroupedTimelineGrouper.group(
            events: [],
            filter: { _ in true },
            values: defaultValues(),
            now: now
        )
        XCTAssertTrue(groups.isEmpty, "Empty events should produce empty groups")
    }

    // MARK: - Author Grouping

    func testEventsGroupedByAuthor() {
        let event1 = makeEvent(content: "First post from author one", keypair: test_keypair, secondsAgo: 200)
        let event2 = makeEvent(content: "Second post from author one", keypair: test_keypair, secondsAgo: 100)
        let event3 = makeEvent(content: "Post from jack who is a different author", keypair: jack_keypair, secondsAgo: 150)

        let groups = GroupedTimelineGrouper.group(
            events: [event1, event2, event3],
            filter: { _ in true },
            values: defaultValues(),
            now: now
        )

        XCTAssertEqual(groups.count, 2, "Should have 2 author groups")

        let testKeyGroup = groups.first(where: { $0.pubkey == test_keypair.pubkey })
        XCTAssertNotNil(testKeyGroup)
        XCTAssertEqual(testKeyGroup?.postCount, 2, "test_keypair author should have 2 posts")
        XCTAssertEqual(testKeyGroup?.latestEvent.id, event2.id, "Latest event should be the more recent one")

        let jackGroup = groups.first(where: { $0.pubkey == jack_keypair.pubkey })
        XCTAssertNotNil(jackGroup)
        XCTAssertEqual(jackGroup?.postCount, 1, "jack_keypair author should have 1 post")
    }

    func testGroupsSortedByMostRecentActivity() {
        let olderEvent = makeEvent(content: "Older post from test keypair author", keypair: test_keypair, secondsAgo: 500)
        let newerEvent = makeEvent(content: "Newer post from jack keypair author", keypair: jack_keypair, secondsAgo: 50)

        let groups = GroupedTimelineGrouper.group(
            events: [olderEvent, newerEvent],
            filter: { _ in true },
            values: defaultValues(),
            now: now
        )

        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].pubkey, jack_keypair.pubkey, "Most recent author should be first")
        XCTAssertEqual(groups[1].pubkey, test_keypair.pubkey, "Older author should be second")
    }

    // MARK: - Reply Filtering

    func testRepliesExcludedWhenIncludeRepliesFalse() {
        let replyTag = [["e", String(repeating: "a", count: 64)]]
        let normalEvent = makeEvent(content: "Normal post with enough content to pass", keypair: test_keypair, secondsAgo: 100)
        let replyEvent = makeEvent(content: "Reply post with enough content to pass", keypair: test_keypair, secondsAgo: 200, tags: replyTag)

        let groups = GroupedTimelineGrouper.group(
            events: [normalEvent, replyEvent],
            filter: { _ in true },
            values: defaultValues(includeReplies: false),
            now: now
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].postCount, 1, "Only non-reply should be counted")
        XCTAssertEqual(groups[0].latestEvent.id, normalEvent.id)
    }

    func testRepliesIncludedWhenIncludeRepliesTrue() {
        let replyTag = [["e", String(repeating: "a", count: 64)]]
        let normalEvent = makeEvent(content: "Normal post with enough content to pass", keypair: test_keypair, secondsAgo: 100)
        let replyEvent = makeEvent(content: "Reply post with enough content to pass", keypair: test_keypair, secondsAgo: 200, tags: replyTag)

        let groups = GroupedTimelineGrouper.group(
            events: [normalEvent, replyEvent],
            filter: { _ in true },
            values: defaultValues(includeReplies: true),
            now: now
        )

        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups[0].postCount, 2, "Both normal and reply should be counted")
    }

    // MARK: - Time Range Filtering

    func testEventsOutsideTimeRangeExcluded() {
        let recentEvent = makeEvent(content: "Recent post within the time range", keypair: test_keypair, secondsAgo: 100)
        let oldEvent = makeEvent(content: "Old post outside the time range", keypair: jack_keypair, secondsAgo: 90000) // > 24h

        let groups = GroupedTimelineGrouper.group(
            events: [recentEvent, oldEvent],
            filter: { _ in true },
            values: defaultValues(),
            now: now
        )

        XCTAssertEqual(groups.count, 1, "Only recent event should be included")
        XCTAssertEqual(groups[0].pubkey, test_keypair.pubkey)
    }

    // MARK: - Keyword Filtering

    func testEventsWithFilteredWordsExcluded() {
        let normalEvent = makeEvent(content: "This is a normal post without bad words", keypair: test_keypair)
        let filteredEvent = makeEvent(content: "This post mentions bitcoin and other stuff", keypair: jack_keypair)

        let groups = GroupedTimelineGrouper.group(
            events: [normalEvent, filteredEvent],
            filter: { _ in true },
            values: defaultValues(filteredWords: "bitcoin"),
            now: now
        )

        XCTAssertEqual(groups.count, 1, "Event with filtered word should be excluded")
        XCTAssertEqual(groups[0].pubkey, test_keypair.pubkey)
    }

    func testShortFilterWordsIgnored() {
        let event = makeEvent(content: "A post that contains the letter a and b", keypair: test_keypair)

        let groups = GroupedTimelineGrouper.group(
            events: [event],
            filter: { _ in true },
            values: defaultValues(filteredWords: "a,b"),
            now: now
        )

        XCTAssertEqual(groups.count, 1, "Single-char filter words should be ignored")
    }

    // MARK: - Max Notes Per User

    func testMaxNotesPerUserExcludesProlificAuthors() {
        let events = (0..<5).map { i in
            makeEvent(content: "Post number \(i) from a prolific author user", keypair: test_keypair, secondsAgo: UInt32(100 + i))
        }
        let singleEvent = makeEvent(content: "Single post from jack who posts less", keypair: jack_keypair, secondsAgo: 50)

        let groups = GroupedTimelineGrouper.group(
            events: events + [singleEvent],
            filter: { _ in true },
            values: defaultValues(maxNotesPerUser: 3),
            now: now
        )

        XCTAssertEqual(groups.count, 1, "Author with 5 posts should be excluded (max 3)")
        XCTAssertEqual(groups[0].pubkey, jack_keypair.pubkey)
    }

    // MARK: - Short Note Filtering

    func testShortNotesExcludedWhenEnabled() {
        let shortEvent = makeEvent(content: "Hi", keypair: test_keypair)
        let normalEvent = makeEvent(content: "This is a longer note with plenty of words in it", keypair: jack_keypair)

        let groups = GroupedTimelineGrouper.group(
            events: [shortEvent, normalEvent],
            filter: { _ in true },
            values: defaultValues(hideShortNotes: true),
            now: now
        )

        XCTAssertEqual(groups.count, 1, "Short note should be excluded")
        XCTAssertEqual(groups[0].pubkey, jack_keypair.pubkey)
    }

    func testShortNotesIncludedWhenDisabled() {
        let shortEvent = makeEvent(content: "Hi", keypair: test_keypair)
        let normalEvent = makeEvent(content: "This is a longer note with plenty of words in it", keypair: jack_keypair)

        let groups = GroupedTimelineGrouper.group(
            events: [shortEvent, normalEvent],
            filter: { _ in true },
            values: defaultValues(hideShortNotes: false),
            now: now
        )

        XCTAssertEqual(groups.count, 2, "Short note should be included when filter disabled")
    }

    func testSingleWordExcludedWhenHideShortEnabled() {
        let singleWordEvent = makeEvent(content: "Supercalifragilisticexpialidocious", keypair: test_keypair)

        let groups = GroupedTimelineGrouper.group(
            events: [singleWordEvent],
            filter: { _ in true },
            values: defaultValues(hideShortNotes: true),
            now: now
        )

        XCTAssertTrue(groups.isEmpty, "Single-word note should be excluded")
    }

    // MARK: - Content Filter Passthrough

    func testContentFilterBlocksEvents() {
        let event1 = makeEvent(content: "This event should be allowed through the filter", keypair: test_keypair)
        let event2 = makeEvent(content: "This event should be blocked by the filter", keypair: jack_keypair)

        let groups = GroupedTimelineGrouper.group(
            events: [event1, event2],
            filter: { $0.pubkey == test_keypair.pubkey },
            values: defaultValues(),
            now: now
        )

        XCTAssertEqual(groups.count, 1, "Content filter should block events")
        XCTAssertEqual(groups[0].pubkey, test_keypair.pubkey)
    }

    // MARK: - Parse Filtered Words

    func testParseFilteredWordsTrimsAndLowercases() {
        let words = GroupedTimelineGrouper.parseFilteredWords("  Bitcoin , NOSTR , gm ")
        XCTAssertEqual(words, ["bitcoin", "nostr", "gm"])
    }

    func testParseFilteredWordsIgnoresShortWords() {
        let words = GroupedTimelineGrouper.parseFilteredWords("a,bb,c,dd")
        XCTAssertEqual(words, ["bb", "dd"], "Words shorter than 2 chars should be excluded")
    }
}
