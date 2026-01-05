//
//  EventNetworkTests.swift
//  damusTests
//
//  Tests for various Nostr event types under poor network conditions.
//  Covers reactions, boosts, follows, and other event publishing.
//

import Foundation
import XCTest
@testable import damus

// MARK: - Reactions Network Tests

/// Tests for reaction (kind 7) events under poor network conditions.
final class ReactionNetworkTests: XCTestCase {

    var pool: RelayPool!
    var postbox: PostBox!
    var mockSocket: MockWebSocket!
    var ndb: Ndb!

    let testRelayURL = RelayURL("wss://test.relay.com")!

    override func setUp() async throws {
        try await super.setUp()
        ndb = Ndb.test
        pool = RelayPool(ndb: ndb)

        mockSocket = MockWebSocket()
        let descriptor = RelayPool.RelayDescriptor(url: testRelayURL, info: .readWrite)
        try await pool.add_relay(descriptor, webSocket: mockSocket)

        postbox = PostBox(pool: pool)

        await pool.connect()
        mockSocket.simulateConnect()
        try await Task.sleep(for: .milliseconds(100))
    }

    override func tearDown() async throws {
        await pool.close()
        pool = nil
        postbox = nil
        mockSocket = nil
        ndb = nil
        try await super.tearDown()
    }

    /// Creates a test text note to react to.
    func makeTestNote(content: String = "Test note") -> NostrEvent? {
        return NostrEvent(content: content, keypair: test_keypair, kind: 1, tags: [])
    }

    /// Simulates OK response from relay.
    func simulateOKResponse(eventId: NoteId, success: Bool = true) {
        let result = CommandResult(event_id: eventId, ok: success, msg: "")
        postbox.handle_event(relay_id: testRelayURL, .nostr_event(.ok(result)))
    }

    // MARK: - Reaction Publishing Tests

    /// Test: Like event (kind 7) is sent to relay
    func testLikeEventSentToRelay() async throws {
        guard let note = makeTestNote() else {
            XCTFail("Failed to create test note")
            return
        }

        guard let like = make_like_event(keypair: test_keypair_full, liked: note, relayURL: nil) else {
            XCTFail("Failed to create like event")
            return
        }

        await postbox.send(like, to: [testRelayURL])

        try await Task.sleep(for: .milliseconds(100))

        XCTAssertGreaterThan(mockSocket.sentMessages.count, 0, "Should send reaction")

        if let sentMessage = mockSocket.sentMessages.first,
           case .string(let str) = sentMessage {
            XCTAssertTrue(str.contains("EVENT"), "Should be EVENT message")
            XCTAssertTrue(str.contains("\"kind\":7"), "Should be kind 7 (reaction)")
        }
    }

    /// Test: Reaction removed from queue on OK
    func testReactionRemovedOnOK() async throws {
        guard let note = makeTestNote(),
              let like = make_like_event(keypair: test_keypair_full, liked: note, relayURL: nil) else {
            XCTFail("Failed to create events")
            return
        }

        await postbox.send(like, to: [testRelayURL])
        XCTAssertNotNil(postbox.events[like.id])

        simulateOKResponse(eventId: like.id)

        XCTAssertNil(postbox.events[like.id], "Reaction should be removed after OK")
    }

    /// Test: Reaction queued when relay disconnected
    func testReactionQueuedWhenDisconnected() async throws {
        mockSocket.simulateDisconnect()
        try await Task.sleep(for: .milliseconds(100))

        guard let note = makeTestNote(),
              let like = make_like_event(keypair: test_keypair_full, liked: note, relayURL: nil) else {
            XCTFail("Failed to create events")
            return
        }

        mockSocket.reset()

        await postbox.send(like, to: [testRelayURL])

        XCTAssertNotNil(postbox.events[like.id], "Reaction should be queued")
        XCTAssertEqual(mockSocket.sentMessages.count, 0, "No messages sent while disconnected")
    }

    /// Test: Custom emoji reaction
    func testCustomEmojiReaction() async throws {
        guard let note = makeTestNote(),
              let reaction = make_like_event(keypair: test_keypair_full, liked: note, content: "🔥", relayURL: nil) else {
            XCTFail("Failed to create events")
            return
        }

        XCTAssertEqual(reaction.content, "🔥", "Should have custom emoji content")
        XCTAssertEqual(reaction.kind, 7, "Should be kind 7")

        await postbox.send(reaction, to: [testRelayURL])

        try await Task.sleep(for: .milliseconds(100))

        if let sentMessage = mockSocket.sentMessages.first,
           case .string(let str) = sentMessage {
            XCTAssertTrue(str.contains("🔥"), "Should contain custom emoji")
        }
    }

    /// Test: Multiple reactions sent to multiple relays
    func testReactionMultiRelay() async throws {
        let relay2URL = RelayURL("wss://relay2.test.com")!
        let mockSocket2 = MockWebSocket()
        let descriptor2 = RelayPool.RelayDescriptor(url: relay2URL, info: .readWrite)
        try await pool.add_relay(descriptor2, webSocket: mockSocket2)
        mockSocket2.simulateConnect()
        try await Task.sleep(for: .milliseconds(100))

        guard let note = makeTestNote(),
              let like = make_like_event(keypair: test_keypair_full, liked: note, relayURL: nil) else {
            XCTFail("Failed to create events")
            return
        }

        await postbox.send(like, to: [testRelayURL, relay2URL])

        let postedEvent = postbox.events[like.id]
        XCTAssertNotNil(postedEvent)
        XCTAssertEqual(postedEvent?.remaining.count, 2, "Should target 2 relays")
    }
}

// MARK: - Boost Network Tests

/// Tests for boost/repost (kind 6) events under poor network conditions.
final class BoostNetworkTests: XCTestCase {

    var pool: RelayPool!
    var postbox: PostBox!
    var mockSocket: MockWebSocket!
    var ndb: Ndb!

    let testRelayURL = RelayURL("wss://test.relay.com")!

    override func setUp() async throws {
        try await super.setUp()
        ndb = Ndb.test
        pool = RelayPool(ndb: ndb)

        mockSocket = MockWebSocket()
        let descriptor = RelayPool.RelayDescriptor(url: testRelayURL, info: .readWrite)
        try await pool.add_relay(descriptor, webSocket: mockSocket)

        postbox = PostBox(pool: pool)

        await pool.connect()
        mockSocket.simulateConnect()
        try await Task.sleep(for: .milliseconds(100))
    }

    override func tearDown() async throws {
        await pool.close()
        pool = nil
        postbox = nil
        mockSocket = nil
        ndb = nil
        try await super.tearDown()
    }

    /// Creates a test text note to boost.
    func makeTestNote(content: String = "Test note") -> NostrEvent? {
        return NostrEvent(content: content, keypair: test_keypair, kind: 1, tags: [])
    }

    /// Simulates OK response from relay.
    func simulateOKResponse(eventId: NoteId) {
        let result = CommandResult(event_id: eventId, ok: true, msg: "")
        postbox.handle_event(relay_id: testRelayURL, .nostr_event(.ok(result)))
    }

    // MARK: - Boost Publishing Tests

    /// Test: Boost event (kind 6) is sent to relay
    func testBoostEventSentToRelay() async throws {
        guard let note = makeTestNote() else {
            XCTFail("Failed to create test note")
            return
        }

        guard let boost = make_boost_event(keypair: test_keypair_full, boosted: note, relayURL: nil) else {
            XCTFail("Failed to create boost event")
            return
        }

        await postbox.send(boost, to: [testRelayURL])

        try await Task.sleep(for: .milliseconds(100))

        XCTAssertGreaterThan(mockSocket.sentMessages.count, 0, "Should send boost")

        if let sentMessage = mockSocket.sentMessages.first,
           case .string(let str) = sentMessage {
            XCTAssertTrue(str.contains("EVENT"), "Should be EVENT message")
            XCTAssertTrue(str.contains("\"kind\":6"), "Should be kind 6 (boost)")
        }
    }

    /// Test: Boost removed from queue on OK
    func testBoostRemovedOnOK() async throws {
        guard let note = makeTestNote(),
              let boost = make_boost_event(keypair: test_keypair_full, boosted: note, relayURL: nil) else {
            XCTFail("Failed to create events")
            return
        }

        await postbox.send(boost, to: [testRelayURL])
        XCTAssertNotNil(postbox.events[boost.id])

        simulateOKResponse(eventId: boost.id)

        XCTAssertNil(postbox.events[boost.id], "Boost should be removed after OK")
    }

    /// Test: Boost queued when relay disconnected
    func testBoostQueuedWhenDisconnected() async throws {
        mockSocket.simulateDisconnect()
        try await Task.sleep(for: .milliseconds(100))

        guard let note = makeTestNote(),
              let boost = make_boost_event(keypair: test_keypair_full, boosted: note, relayURL: nil) else {
            XCTFail("Failed to create events")
            return
        }

        mockSocket.reset()

        await postbox.send(boost, to: [testRelayURL])

        XCTAssertNotNil(postbox.events[boost.id], "Boost should be queued")
        XCTAssertEqual(mockSocket.sentMessages.count, 0, "No messages sent while disconnected")
    }

    /// Test: Boost content contains original event JSON
    func testBoostContentContainsOriginalEvent() async throws {
        guard let note = makeTestNote(content: "Original content to boost"),
              let boost = make_boost_event(keypair: test_keypair_full, boosted: note, relayURL: nil) else {
            XCTFail("Failed to create events")
            return
        }

        XCTAssertTrue(boost.content.contains("Original content to boost"),
                      "Boost should contain original note content")
        XCTAssertEqual(boost.kind, 6, "Should be kind 6")
    }

    /// Test: Boost includes proper e and p tags
    func testBoostIncludesProperTags() async throws {
        guard let note = makeTestNote(),
              let boost = make_boost_event(keypair: test_keypair_full, boosted: note, relayURL: nil) else {
            XCTFail("Failed to create events")
            return
        }

        // Boost should reference the original note's id and author
        XCTAssertTrue(boost.referenced_ids.contains(note.id), "Should reference original note id")
        XCTAssertTrue(boost.referenced_pubkeys.contains(note.pubkey), "Should reference original author")
    }
}

// MARK: - Follow Network Tests

/// Tests for follow list (kind 3) events under poor network conditions.
final class FollowNetworkTests: XCTestCase {

    var pool: RelayPool!
    var postbox: PostBox!
    var mockSocket: MockWebSocket!
    var ndb: Ndb!

    let testRelayURL = RelayURL("wss://test.relay.com")!

    override func setUp() async throws {
        try await super.setUp()
        ndb = Ndb.test
        pool = RelayPool(ndb: ndb)

        mockSocket = MockWebSocket()
        let descriptor = RelayPool.RelayDescriptor(url: testRelayURL, info: .readWrite)
        try await pool.add_relay(descriptor, webSocket: mockSocket)

        postbox = PostBox(pool: pool)

        await pool.connect()
        mockSocket.simulateConnect()
        try await Task.sleep(for: .milliseconds(100))
    }

    override func tearDown() async throws {
        await pool.close()
        pool = nil
        postbox = nil
        mockSocket = nil
        ndb = nil
        try await super.tearDown()
    }

    /// Creates a follow list event with given pubkeys.
    func makeFollowListEvent(following: [Pubkey]) -> NostrEvent? {
        let tags = following.map { ["p", $0.hex()] }
        return NostrEvent(content: "", keypair: test_keypair, kind: NostrKind.follow_list.rawValue, tags: tags)
    }

    /// Simulates OK response from relay.
    func simulateOKResponse(eventId: NoteId) {
        let result = CommandResult(event_id: eventId, ok: true, msg: "")
        postbox.handle_event(relay_id: testRelayURL, .nostr_event(.ok(result)))
    }

    // MARK: - Follow List Publishing Tests

    /// Test: Follow list (kind 3) is sent to relay
    func testFollowListSentToRelay() async throws {
        let pubkeyToFollow = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!

        guard let followList = makeFollowListEvent(following: [pubkeyToFollow]) else {
            XCTFail("Failed to create follow list event")
            return
        }

        await postbox.send(followList, to: [testRelayURL])

        try await Task.sleep(for: .milliseconds(100))

        XCTAssertGreaterThan(mockSocket.sentMessages.count, 0, "Should send follow list")

        if let sentMessage = mockSocket.sentMessages.first,
           case .string(let str) = sentMessage {
            XCTAssertTrue(str.contains("EVENT"), "Should be EVENT message")
            XCTAssertTrue(str.contains("\"kind\":3"), "Should be kind 3 (follow list)")
        }
    }

    /// Test: Follow list removed from queue on OK
    func testFollowListRemovedOnOK() async throws {
        let pubkeyToFollow = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!

        guard let followList = makeFollowListEvent(following: [pubkeyToFollow]) else {
            XCTFail("Failed to create follow list event")
            return
        }

        await postbox.send(followList, to: [testRelayURL])
        XCTAssertNotNil(postbox.events[followList.id])

        simulateOKResponse(eventId: followList.id)

        XCTAssertNil(postbox.events[followList.id], "Follow list should be removed after OK")
    }

    /// Test: Follow list queued when relay disconnected
    func testFollowListQueuedWhenDisconnected() async throws {
        mockSocket.simulateDisconnect()
        try await Task.sleep(for: .milliseconds(100))

        let pubkeyToFollow = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!

        guard let followList = makeFollowListEvent(following: [pubkeyToFollow]) else {
            XCTFail("Failed to create follow list event")
            return
        }

        mockSocket.reset()

        await postbox.send(followList, to: [testRelayURL])

        XCTAssertNotNil(postbox.events[followList.id], "Follow list should be queued")
        XCTAssertEqual(mockSocket.sentMessages.count, 0, "No messages sent while disconnected")
    }

    /// Test: Follow list with multiple pubkeys
    func testFollowListMultiplePubkeys() async throws {
        let pubkey1 = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let pubkey2 = Pubkey(hex: "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d")!
        let pubkey3 = Pubkey(hex: "82341f882b6eabcd2ba7f1ef90aad961cf074af15b9ef44a09f9d2a8fbfbe6a2")!

        guard let followList = makeFollowListEvent(following: [pubkey1, pubkey2, pubkey3]) else {
            XCTFail("Failed to create follow list event")
            return
        }

        XCTAssertEqual(Array(followList.referenced_pubkeys).count, 3, "Should have 3 pubkeys in follow list")

        await postbox.send(followList, to: [testRelayURL])

        try await Task.sleep(for: .milliseconds(100))

        if let sentMessage = mockSocket.sentMessages.first,
           case .string(let str) = sentMessage {
            XCTAssertTrue(str.contains(pubkey1.hex()), "Should contain first pubkey")
            XCTAssertTrue(str.contains(pubkey2.hex()), "Should contain second pubkey")
            XCTAssertTrue(str.contains(pubkey3.hex()), "Should contain third pubkey")
        }
    }

    /// Test: Follow list sent to multiple relays for redundancy
    func testFollowListMultiRelay() async throws {
        let relay2URL = RelayURL("wss://relay2.test.com")!
        let mockSocket2 = MockWebSocket()
        let descriptor2 = RelayPool.RelayDescriptor(url: relay2URL, info: .readWrite)
        try await pool.add_relay(descriptor2, webSocket: mockSocket2)
        mockSocket2.simulateConnect()
        try await Task.sleep(for: .milliseconds(100))

        let pubkeyToFollow = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!

        guard let followList = makeFollowListEvent(following: [pubkeyToFollow]) else {
            XCTFail("Failed to create follow list event")
            return
        }

        await postbox.send(followList, to: [testRelayURL, relay2URL])

        let postedEvent = postbox.events[followList.id]
        XCTAssertNotNil(postedEvent)
        XCTAssertEqual(postedEvent?.remaining.count, 2, "Should target 2 relays")
    }
}

// MARK: - Mute List Network Tests

/// Tests for mute list events under poor network conditions.
final class MuteListNetworkTests: XCTestCase {

    var pool: RelayPool!
    var postbox: PostBox!
    var mockSocket: MockWebSocket!
    var ndb: Ndb!

    let testRelayURL = RelayURL("wss://test.relay.com")!

    override func setUp() async throws {
        try await super.setUp()
        ndb = Ndb.test
        pool = RelayPool(ndb: ndb)

        mockSocket = MockWebSocket()
        let descriptor = RelayPool.RelayDescriptor(url: testRelayURL, info: .readWrite)
        try await pool.add_relay(descriptor, webSocket: mockSocket)

        postbox = PostBox(pool: pool)

        await pool.connect()
        mockSocket.simulateConnect()
        try await Task.sleep(for: .milliseconds(100))
    }

    override func tearDown() async throws {
        await pool.close()
        pool = nil
        postbox = nil
        mockSocket = nil
        ndb = nil
        try await super.tearDown()
    }

    /// Creates a mute list event (kind 10000).
    func makeMuteListEvent(muted: [Pubkey]) -> NostrEvent? {
        let tags = muted.map { ["p", $0.hex()] }
        return NostrEvent(content: "", keypair: test_keypair, kind: 10000, tags: tags)
    }

    /// Simulates OK response from relay.
    func simulateOKResponse(eventId: NoteId) {
        let result = CommandResult(event_id: eventId, ok: true, msg: "")
        postbox.handle_event(relay_id: testRelayURL, .nostr_event(.ok(result)))
    }

    // MARK: - Mute List Publishing Tests

    /// Test: Mute list is sent to relay
    func testMuteListSentToRelay() async throws {
        let pubkeyToMute = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!

        guard let muteList = makeMuteListEvent(muted: [pubkeyToMute]) else {
            XCTFail("Failed to create mute list event")
            return
        }

        await postbox.send(muteList, to: [testRelayURL])

        try await Task.sleep(for: .milliseconds(100))

        XCTAssertGreaterThan(mockSocket.sentMessages.count, 0, "Should send mute list")

        if let sentMessage = mockSocket.sentMessages.first,
           case .string(let str) = sentMessage {
            XCTAssertTrue(str.contains("EVENT"), "Should be EVENT message")
            XCTAssertTrue(str.contains("\"kind\":10000"), "Should be kind 10000 (mute list)")
        }
    }

    /// Test: Mute list removed from queue on OK
    func testMuteListRemovedOnOK() async throws {
        let pubkeyToMute = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!

        guard let muteList = makeMuteListEvent(muted: [pubkeyToMute]) else {
            XCTFail("Failed to create mute list event")
            return
        }

        await postbox.send(muteList, to: [testRelayURL])
        XCTAssertNotNil(postbox.events[muteList.id])

        simulateOKResponse(eventId: muteList.id)

        XCTAssertNil(postbox.events[muteList.id], "Mute list should be removed after OK")
    }

    /// Test: Mute list queued when relay disconnected
    func testMuteListQueuedWhenDisconnected() async throws {
        mockSocket.simulateDisconnect()
        try await Task.sleep(for: .milliseconds(100))

        let pubkeyToMute = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!

        guard let muteList = makeMuteListEvent(muted: [pubkeyToMute]) else {
            XCTFail("Failed to create mute list event")
            return
        }

        mockSocket.reset()

        await postbox.send(muteList, to: [testRelayURL])

        XCTAssertNotNil(postbox.events[muteList.id], "Mute list should be queued")
        XCTAssertEqual(mockSocket.sentMessages.count, 0, "No messages sent while disconnected")
    }
}

// MARK: - Bookmark List Network Tests

/// Tests for bookmark list events under poor network conditions.
final class BookmarkListNetworkTests: XCTestCase {

    var pool: RelayPool!
    var postbox: PostBox!
    var mockSocket: MockWebSocket!
    var ndb: Ndb!

    let testRelayURL = RelayURL("wss://test.relay.com")!

    override func setUp() async throws {
        try await super.setUp()
        ndb = Ndb.test
        pool = RelayPool(ndb: ndb)

        mockSocket = MockWebSocket()
        let descriptor = RelayPool.RelayDescriptor(url: testRelayURL, info: .readWrite)
        try await pool.add_relay(descriptor, webSocket: mockSocket)

        postbox = PostBox(pool: pool)

        await pool.connect()
        mockSocket.simulateConnect()
        try await Task.sleep(for: .milliseconds(100))
    }

    override func tearDown() async throws {
        await pool.close()
        pool = nil
        postbox = nil
        mockSocket = nil
        ndb = nil
        try await super.tearDown()
    }

    /// Creates a bookmark list event (kind 10003).
    func makeBookmarkListEvent(bookmarkedNoteIds: [NoteId]) -> NostrEvent? {
        let tags = bookmarkedNoteIds.map { ["e", $0.hex()] }
        return NostrEvent(content: "", keypair: test_keypair, kind: 10003, tags: tags)
    }

    /// Simulates OK response from relay.
    func simulateOKResponse(eventId: NoteId) {
        let result = CommandResult(event_id: eventId, ok: true, msg: "")
        postbox.handle_event(relay_id: testRelayURL, .nostr_event(.ok(result)))
    }

    // MARK: - Bookmark List Publishing Tests

    /// Test: Bookmark list is sent to relay
    func testBookmarkListSentToRelay() async throws {
        let noteToBookmark = NoteId(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!

        guard let bookmarkList = makeBookmarkListEvent(bookmarkedNoteIds: [noteToBookmark]) else {
            XCTFail("Failed to create bookmark list event")
            return
        }

        await postbox.send(bookmarkList, to: [testRelayURL])

        try await Task.sleep(for: .milliseconds(100))

        XCTAssertGreaterThan(mockSocket.sentMessages.count, 0, "Should send bookmark list")

        if let sentMessage = mockSocket.sentMessages.first,
           case .string(let str) = sentMessage {
            XCTAssertTrue(str.contains("EVENT"), "Should be EVENT message")
            XCTAssertTrue(str.contains("\"kind\":10003"), "Should be kind 10003 (bookmark list)")
        }
    }

    /// Test: Bookmark list removed from queue on OK
    func testBookmarkListRemovedOnOK() async throws {
        let noteToBookmark = NoteId(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!

        guard let bookmarkList = makeBookmarkListEvent(bookmarkedNoteIds: [noteToBookmark]) else {
            XCTFail("Failed to create bookmark list event")
            return
        }

        await postbox.send(bookmarkList, to: [testRelayURL])
        XCTAssertNotNil(postbox.events[bookmarkList.id])

        simulateOKResponse(eventId: bookmarkList.id)

        XCTAssertNil(postbox.events[bookmarkList.id], "Bookmark list should be removed after OK")
    }

    /// Test: Bookmark list queued when relay disconnected
    func testBookmarkListQueuedWhenDisconnected() async throws {
        mockSocket.simulateDisconnect()
        try await Task.sleep(for: .milliseconds(100))

        let noteToBookmark = NoteId(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!

        guard let bookmarkList = makeBookmarkListEvent(bookmarkedNoteIds: [noteToBookmark]) else {
            XCTFail("Failed to create bookmark list event")
            return
        }

        mockSocket.reset()

        await postbox.send(bookmarkList, to: [testRelayURL])

        XCTAssertNotNil(postbox.events[bookmarkList.id], "Bookmark list should be queued")
        XCTAssertEqual(mockSocket.sentMessages.count, 0, "No messages sent while disconnected")
    }
}
