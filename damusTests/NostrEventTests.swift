//
//  NostrEventTests.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2023-08-15.
//

import Foundation
import XCTest
@testable import damus

final class NostrEventTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    /// Based on https://github.com/damus-io/damus/issues/1468
    /// Tests whether `decode_nostr_event` correctly decodes nostr note image content written with optional escaped slashes
    func testDecodeNostrEventWithEscapedSlashes() throws {
        let testMessageString = "[\"EVENT\",\"A54091AC-D144-49F6-853A-2141A5EA09B6\",{\"content\":\"{\\\"tags\\\":[],\\\"pubkey\\\":\\\"f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9\\\",\\\"content\\\":\\\"https:\\\\/\\\\/cdn.nostr.build\\\\/i\\\\/5c1d3296f66c2630131bf123106486aeaf051ed8466031c0e0532d70b33cddb2.jpg\\\",\\\"created_at\\\":1691864981,\\\"kind\\\":1,\\\"sig\\\":\\\"fc0033aa3d4df50b692a5b346fa816fdded698de2045e36e0642a021391468c44ca69c2471adc7e92088131872d4aaa1e90ea6e1ad97f3cc748f4aed96dfae18\\\",\\\"id\\\":\\\"e8f6eca3b161abba034dac9a02bb6930ecde9fd2fb5d6c5f22a05526e11382cb\\\"}\",\"created_at\":1691866192,\"id\":\"56e3f14cedab76762afef78eeb34b07ce1313543a2f3365a7b99fd5daa65abc9\",\"kind\":6,\"pubkey\":\"32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245\",\"sig\":\"3c1161c3b03cafe13e2d9d624b158bdb74867caf61df158871633c859cd587e7779d096680de34024d9acfcba9aa3cb76fdbfa20227afb7e03a9ab588e6b77c9\",\"tags\":[[\"e\",\"e8f6eca3b161abba034dac9a02bb6930ecde9fd2fb5d6c5f22a05526e11382cb\",\"\",\"root\"],[\"p\",\"f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9\"]]}]"
        let response: NostrResponse = decode_nostr_event(txt: testMessageString)!
        guard case .event(_, let testEvent) = response else {
            XCTAssert(false, "Could not decode event")
            return
        }
        let urlInContent = "https:\\/\\/cdn.nostr.build\\/i\\/5c1d3296f66c2630131bf123106486aeaf051ed8466031c0e0532d70b33cddb2.jpg"
        XCTAssert(testEvent.content.contains(urlInContent), "Issue parsing event. Expected to see '\(urlInContent)' inside \(testEvent.content)")
        
        let testMessageString2 = "[\"EVENT\",\"A54091AC-D144-49F6-853A-2141A5EA09B6\",{\"content\":\"{\\\"tags\\\":[],\\\"pubkey\\\":\\\"f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9\\\",\\\"content\\\":\\\"https:\\/\\/cdn.nostr.build\\/i\\/5c1d3296f66c2630131bf123106486aeaf051ed8466031c0e0532d70b33cddb2.jpg\\\",\\\"created_at\\\":1691864981,\\\"kind\\\":1,\\\"sig\\\":\\\"fc0033aa3d4df50b692a5b346fa816fdded698de2045e36e0642a021391468c44ca69c2471adc7e92088131872d4aaa1e90ea6e1ad97f3cc748f4aed96dfae18\\\",\\\"id\\\":\\\"e8f6eca3b161abba034dac9a02bb6930ecde9fd2fb5d6c5f22a05526e11382cb\\\"}\",\"created_at\":1691866192,\"id\":\"56e3f14cedab76762afef78eeb34b07ce1313543a2f3365a7b99fd5daa65abc9\",\"kind\":6,\"pubkey\":\"32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245\",\"sig\":\"3c1161c3b03cafe13e2d9d624b158bdb74867caf61df158871633c859cd587e7779d096680de34024d9acfcba9aa3cb76fdbfa20227afb7e03a9ab588e6b77c9\",\"tags\":[[\"e\",\"e8f6eca3b161abba034dac9a02bb6930ecde9fd2fb5d6c5f22a05526e11382cb\",\"\",\"root\"],[\"p\",\"f8e6c64342f1e052480630e27e1016dce35fc3a614e60434fef4aa2503328ca9\"]]}]"
        let response2: NostrResponse = decode_nostr_event(txt: testMessageString2)!
        guard case .event(_, let testEvent2) = response2 else {
            XCTAssert(false, "Could not decode event")
            return
        }
        let urlInContent2 = "https://cdn.nostr.build/i/5c1d3296f66c2630131bf123106486aeaf051ed8466031c0e0532d70b33cddb2.jpg"
        XCTAssert(testEvent2.content.contains(urlInContent2), "Issue parsing event. Expected to see '\(urlInContent2)' inside \(testEvent2.content)")
    }
}

final class VineVideoTests: XCTestCase {
    func testPrefersExplicitMp4OverStreaming() {
        let tags: [[String]] = [
            ["d", "vine-prefers-mp4"],
            ["imeta", "url", "https://example.com/video.m3u8", "m", "application/x-mpegURL"],
            ["imeta", "url", "https://example.com/video.mp4", "m", "video/mp4"]
        ]
        let video = VineVideo(event: makeVineEvent(tags: tags))
        XCTAssertEqual(video?.playbackURL?.absoluteString, "https://example.com/video.mp4")
    }
    
    func testExtractsURLFromContentWhenTagsMissing() {
        let content = "Here is a clip https://example.com/moment.mp4"
        let tags: [[String]] = [
            ["d", "vine-content"]
        ]
        let video = VineVideo(event: makeVineEvent(content: content, tags: tags))
        XCTAssertEqual(video?.playbackURL?.absoluteString, "https://example.com/moment.mp4")
    }
    
    func testParsesOriginMetadata() {
        let tags: [[String]] = [
            ["d", "vine-origin"],
            ["imeta", "url", "https://example.com/video.mp4", "m", "video/mp4"],
            ["origin", "vine", "abc123", "Recovered"]
        ]
        let video = VineVideo(event: makeVineEvent(tags: tags))
        XCTAssertEqual(video?.originDescription, "vine • abc123 – Recovered")
    }
    
    func testUsesImetaThumbnailWhenAvailable() {
        let tags: [[String]] = [
            ["d", "vine-thumb"],
            ["imeta", "url", "https://example.com/video.mp4", "m", "video/mp4", "image", "https://example.com/thumb.jpg"]
        ]
        let video = VineVideo(event: makeVineEvent(tags: tags))
        XCTAssertEqual(video?.thumbnailURL?.absoluteString, "https://example.com/thumb.jpg")
    }
    
    func testClassicFixtureParsesStats() {
        let video = VineVideo(event: makeVineEvent(tags: VineFixtures.classicImport))
        XCTAssertEqual(video?.playbackURL?.absoluteString, "https://cdn.divine.video/eab385ddbb6e06b6b5d93de39e5d92b85c33fe0d107eef3262ebe1d259ebc78f.mp4")
        XCTAssertEqual(video?.thumbnailURL?.absoluteString, "https://stream.divine.video/2e3125fb-226e-4668-94b1-0a9a11daf348/thumbnail.jpg")
        XCTAssertEqual(video?.loopCount, 56722111)
        XCTAssertEqual(video?.likeCount, 9363)
        XCTAssertEqual(video?.repostCount, 4457)
        XCTAssertEqual(video?.altText, "Video: He looks so good with his purple hair")
    }
    
    func testFixturePrefersMp4OverStreamingImeta() {
        let video = VineVideo(event: makeVineEvent(tags: VineFixtures.multiIMetaFallback))
        XCTAssertEqual(video?.playbackURL?.absoluteString, "https://cdn.divine.video/7bdcabe6b308b8a1a261c5b5ec1c6d90292664c6d399fdb8a0d05d4197168edd.mp4")
        XCTAssertEqual(video?.thumbnailURL?.absoluteString, "https://stream.divine.video/7a324ede-7a9a-4c5a-bf11-de98c3cd6d02/thumbnail.jpg")
        XCTAssertEqual(video?.hashtags, ["attack"])
    }
    
    func testReplacementKeepsNewestEvent() async {
        let first = makeVineEvent(tags: VineFixtures.replacementOriginal, createdAt: 100)
        let updated = makeVineEvent(tags: VineFixtures.replacementUpdated, createdAt: 200)
        let feed = VineTestFeed()
        await feed.apply(first)
        await feed.apply(updated)
        let vines = await feed.vines
        XCTAssertEqual(vines.count, 1)
        XCTAssertEqual(vines.first?.title, "Updated cut")
    }

    func testReplacementKeepsOldestWhenOlder() async {
        let first = makeVineEvent(tags: VineFixtures.replacementOriginal, createdAt: 200)
        let updated = makeVineEvent(tags: VineFixtures.replacementUpdated, createdAt: 100)
        let feed = VineTestFeed()
        await feed.apply(first)
        await feed.apply(updated)
        let vines = await feed.vines
        XCTAssertEqual(vines.count, 1)
        XCTAssertEqual(vines.first?.title, "First cut")
    }

    func testExpiredVineParsesExpirationTimestamp() {
        let expired = makeVineEvent(tags: VineFixtures.expired, createdAt: 1)
        let video = VineVideo(event: expired)
        XCTAssertNotNil(video)
        XCTAssertEqual(video?.expirationTimestamp, 1)
    }
    
    func testMutedAuthorFiltered() async {
        let vine = makeVineEvent(tags: VineFixtures.mutedAuthor)
        let feed = VineTestFeed()
        await feed.setFilter { _ in false }
        await feed.handle(vine)
        let vines = await feed.vines
        XCTAssertTrue(vines.isEmpty)
    }
    
    // MARK: - Deduplication & Sorting

    func testDedupeKeyUseDTag() {
        let tags: [[String]] = [
            ["d", "my-unique-vine-id"],
            ["imeta", "url", "https://example.com/video.mp4", "m", "video/mp4"]
        ]
        let video = VineVideo(event: makeVineEvent(tags: tags))
        XCTAssertEqual(video?.dedupeKey, "my-unique-vine-id")
    }

    func testDedupeKeyFallsBackToEventIdWhenDTagMissing() {
        let tags: [[String]] = [
            ["imeta", "url", "https://example.com/video.mp4", "m", "video/mp4"]
        ]
        let event = makeVineEvent(tags: tags)
        let video = VineVideo(event: event)
        XCTAssertNotNil(video)
        XCTAssertEqual(video?.dedupeKey, event.id.hex())
    }

    func testDeduplicationKeepsNewestByDedupeKey() async {
        let olderEvent = makeVineEvent(tags: VineFixtures.replacementOriginal, createdAt: 1000)
        let newerEvent = makeVineEvent(tags: VineFixtures.replacementUpdated, createdAt: 2000)
        let feed = VineTestFeed()
        await feed.apply(olderEvent)
        await feed.apply(newerEvent)
        let vines = await feed.vines
        XCTAssertEqual(vines.count, 1, "Two events with the same d tag should deduplicate to one entry")
        XCTAssertEqual(vines.first?.dedupeKey, "repl-vine")
        XCTAssertEqual(vines.first?.createdAt, 2000, "The newer event should be kept")
        XCTAssertEqual(vines.first?.title, "Updated cut")
    }

    func testDeduplicationKeepsExistingWhenIncomingIsOlder() async {
        let newerEvent = makeVineEvent(tags: VineFixtures.replacementUpdated, createdAt: 2000)
        let olderEvent = makeVineEvent(tags: VineFixtures.replacementOriginal, createdAt: 1000)
        let feed = VineTestFeed()
        await feed.apply(newerEvent)
        await feed.apply(olderEvent)
        let vines = await feed.vines
        XCTAssertEqual(vines.count, 1, "Older duplicate should not replace newer entry")
        XCTAssertEqual(vines.first?.createdAt, 2000, "The newer event should still be kept")
        XCTAssertEqual(vines.first?.title, "Updated cut")
    }

    func testSortOrderDescendingByCreatedAt() async {
        let eventA = makeVineEvent(tags: [["d", "vine-a"], ["imeta", "url", "https://example.com/a.mp4", "m", "video/mp4"]], createdAt: 100)
        let eventB = makeVineEvent(tags: [["d", "vine-b"], ["imeta", "url", "https://example.com/b.mp4", "m", "video/mp4"]], createdAt: 300)
        let eventC = makeVineEvent(tags: [["d", "vine-c"], ["imeta", "url", "https://example.com/c.mp4", "m", "video/mp4"]], createdAt: 200)

        let feed = VineTestFeed()
        await feed.apply(eventA)
        await feed.apply(eventB)
        await feed.apply(eventC)
        let vines = await feed.vines

        XCTAssertEqual(vines.count, 3)
        XCTAssertEqual(vines[0].dedupeKey, "vine-b", "Newest event (createdAt 300) should be first")
        XCTAssertEqual(vines[1].dedupeKey, "vine-c", "Middle event (createdAt 200) should be second")
        XCTAssertEqual(vines[2].dedupeKey, "vine-a", "Oldest event (createdAt 100) should be last")
    }

    func testDistinctDTagsAreNotDeduplicated() async {
        let eventA = makeVineEvent(tags: [["d", "vine-alpha"], ["imeta", "url", "https://example.com/alpha.mp4", "m", "video/mp4"]], createdAt: 500)
        let eventB = makeVineEvent(tags: [["d", "vine-beta"], ["imeta", "url", "https://example.com/beta.mp4", "m", "video/mp4"]], createdAt: 500)

        let feed = VineTestFeed()
        await feed.apply(eventA)
        await feed.apply(eventB)
        let vines = await feed.vines

        XCTAssertEqual(vines.count, 2, "Events with distinct d tags should both be present")
        let keys = Set(vines.map(\.dedupeKey))
        XCTAssertTrue(keys.contains("vine-alpha"))
        XCTAssertTrue(keys.contains("vine-beta"))
    }

    // MARK: - Helpers

    private func makeVineEvent(content: String = "", tags: [[String]], createdAt: UInt32 = UInt32(Date().timeIntervalSince1970)) -> NostrEvent {
        let keypair = generate_new_keypair().to_keypair()
        return NostrEvent(content: content, keypair: keypair, kind: NostrKind.vine_short.rawValue, tags: tags, createdAt: createdAt)!
    }
}

/// Tests for VineFeedModel logic (deduplication, page application, prefetch gating)
/// exercised through the VineTestFeed actor that mirrors VineFeedModel's core algorithms
/// without requiring DamusState or a network connection.
final class VineFeedModelTests: XCTestCase {

    // MARK: - Page Application

    func testApplyPageResetSortsDescending() async {
        let events = [
            makeVineEvent(tags: [["d", "p-old"], ["imeta", "url", "https://example.com/old.mp4", "m", "video/mp4"]], createdAt: 100),
            makeVineEvent(tags: [["d", "p-new"], ["imeta", "url", "https://example.com/new.mp4", "m", "video/mp4"]], createdAt: 300),
            makeVineEvent(tags: [["d", "p-mid"], ["imeta", "url", "https://example.com/mid.mp4", "m", "video/mp4"]], createdAt: 200),
        ]
        let feed = VineTestFeed()
        await feed.applyPage(events, reset: true)
        let vines = await feed.vines
        XCTAssertEqual(vines.count, 3)
        XCTAssertEqual(vines.map(\.createdAt), [300, 200, 100], "Reset page should sort descending by createdAt")
    }

    func testApplyPageAppendDeduplicatesAndSorts() async {
        let initial = [
            makeVineEvent(tags: [["d", "existing"], ["imeta", "url", "https://example.com/existing.mp4", "m", "video/mp4"]], createdAt: 500),
        ]
        let feed = VineTestFeed()
        await feed.applyPage(initial, reset: true)

        let olderPage = [
            makeVineEvent(tags: [["d", "existing"], ["imeta", "url", "https://example.com/existing-dup.mp4", "m", "video/mp4"]], createdAt: 400),
            makeVineEvent(tags: [["d", "older"], ["imeta", "url", "https://example.com/older.mp4", "m", "video/mp4"]], createdAt: 300),
        ]
        await feed.applyPage(olderPage, reset: false)
        let vines = await feed.vines

        XCTAssertEqual(vines.count, 2, "Duplicate dedupeKey should be filtered on append")
        XCTAssertEqual(vines[0].dedupeKey, "existing")
        XCTAssertEqual(vines[1].dedupeKey, "older")
        XCTAssertEqual(vines.map(\.createdAt), [500, 300], "Combined list should be sorted descending")
    }

    func testApplyPageEmptyAppendDoesNotAlterExisting() async {
        let initial = [
            makeVineEvent(tags: [["d", "solo"], ["imeta", "url", "https://example.com/solo.mp4", "m", "video/mp4"]], createdAt: 100),
        ]
        let feed = VineTestFeed()
        await feed.applyPage(initial, reset: true)
        await feed.applyPage([], reset: false)
        let vines = await feed.vines
        XCTAssertEqual(vines.count, 1)
        XCTAssertEqual(vines.first?.dedupeKey, "solo")
    }

    // MARK: - Prefetch Gating

    func testShouldPrefetchReturnsFalseWhenConstrained() async {
        let gate = PrefetchGate()
        await gate.setConstrained(true)
        let result = await gate.shouldPrefetch(allowCellular: true)
        XCTAssertFalse(result, "Prefetch should be blocked on constrained paths regardless of cellular preference")
    }

    func testShouldPrefetchReturnsFalseWhenExpensiveAndCellularDisallowed() async {
        let gate = PrefetchGate()
        await gate.setExpensive(true)
        let result = await gate.shouldPrefetch(allowCellular: false)
        XCTAssertFalse(result, "Prefetch should be blocked on expensive paths when cellular prefetch is disallowed")
    }

    func testShouldPrefetchReturnsTrueWhenExpensiveAndCellularAllowed() async {
        let gate = PrefetchGate()
        await gate.setExpensive(true)
        let result = await gate.shouldPrefetch(allowCellular: true)
        XCTAssertTrue(result, "Prefetch should be allowed on expensive paths when cellular prefetch is allowed")
    }

    func testShouldPrefetchReturnsTrueOnUnconstrainedPath() async {
        let gate = PrefetchGate()
        let result = await gate.shouldPrefetch(allowCellular: false)
        XCTAssertTrue(result, "Prefetch should be allowed on unconstrained, non-expensive paths")
    }

    // MARK: - Helpers

    private func makeVineEvent(content: String = "", tags: [[String]], createdAt: UInt32 = UInt32(Date().timeIntervalSince1970)) -> NostrEvent {
        let keypair = generate_new_keypair().to_keypair()
        return NostrEvent(content: content, keypair: keypair, kind: NostrKind.vine_short.rawValue, tags: tags, createdAt: createdAt)!
    }
}

/// Mirrors `VineFeedModel.shouldPrefetchVideos` logic for testing without DamusState.
private actor PrefetchGate {
    private var isExpensive = false
    private var isConstrained = false

    func setExpensive(_ value: Bool) { isExpensive = value }
    func setConstrained(_ value: Bool) { isConstrained = value }

    func shouldPrefetch(allowCellular: Bool) -> Bool {
        if isConstrained { return false }
        if isExpensive && !allowCellular { return false }
        return true
    }
}

private actor VineTestFeed {
    private(set) var vines: [VineVideo] = []
    private var shouldShowEvent: @Sendable (NostrEvent) -> Bool = { _ in true }

    func setFilter(_ predicate: @Sendable @escaping (NostrEvent) -> Bool) {
        shouldShowEvent = predicate
    }

    func apply(_ event: NostrEvent) {
        guard let video = VineVideo(event: event) else { return }
        if let index = vines.firstIndex(where: { $0.dedupeKey == video.dedupeKey }) {
            if vines[index].createdAt >= video.createdAt { return }
            vines[index] = video
        } else {
            vines.append(video)
        }
        vines.sort { $0.createdAt > $1.createdAt }
    }
    
    func handle(_ event: NostrEvent) async {
        guard shouldShowEvent(event) else { return }
        apply(event)
    }

    /// Mirrors VineFeedModel.applyPage for testing page-application logic.
    func applyPage(_ events: [NostrEvent], reset: Bool) {
        var videos = events.compactMap { VineVideo(event: $0) }
        videos.sort { $0.createdAt > $1.createdAt }
        if reset {
            vines = videos
        } else {
            let newVideos = videos.filter { video in
                !vines.contains(where: { $0.dedupeKey == video.dedupeKey })
            }
            vines.append(contentsOf: newVideos)
            vines.sort { $0.createdAt > $1.createdAt }
        }
    }
}
