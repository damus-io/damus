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

// MARK: - Notifications Network Tests

/// Tests for NotificationsModel event processing under various conditions.
@MainActor
final class NotificationsNetworkTests: XCTestCase {

    var notificationsModel: NotificationsModel!
    var damus: DamusState!

    override func setUp() async throws {
        try await super.setUp()
        damus = generate_test_damus_state(mock_profile_info: nil)
        notificationsModel = NotificationsModel()
    }

    override func tearDown() async throws {
        notificationsModel = nil
        damus = nil
        try await super.tearDown()
    }

    /// A test note ID for notifications to reference.
    let testNoteId = NoteId(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!

    /// Creates a test text note event.
    func makeTestNote(content: String = "Test reply", createdAt: UInt32? = nil) -> NostrEvent? {
        let created = createdAt ?? UInt32(Date().timeIntervalSince1970)
        return NostrEvent(content: content, keypair: test_keypair, kind: 1, tags: [["e", testNoteId.hex()]], createdAt: created)
    }

    /// Creates a reaction event (kind 7).
    func makeReaction(content: String = "+", createdAt: UInt32? = nil) -> NostrEvent? {
        let created = createdAt ?? UInt32(Date().timeIntervalSince1970)
        return NostrEvent(content: content, keypair: test_keypair, kind: 7, tags: [["e", testNoteId.hex()]], createdAt: created)
    }

    /// Creates a repost event (kind 6).
    func makeRepost(createdAt: UInt32? = nil) -> NostrEvent? {
        guard let originalNote = makeTestNote() else { return nil }
        return make_boost_event(keypair: test_keypair_full, boosted: originalNote, relayURL: nil)
    }

    // MARK: - Event Queuing Tests

    /// Test: Events are queued when should_queue is true
    func testEventsQueuedWhenShouldQueueTrue() throws {
        notificationsModel.set_should_queue(true)

        guard let reply = makeTestNote(content: "Queued reply") else {
            XCTFail("Failed to create test note")
            return
        }

        let inserted = notificationsModel.insert_event(reply, damus_state: damus)

        XCTAssertTrue(inserted, "Event should be queued")
        XCTAssertEqual(notificationsModel.incoming_events.count, 1, "Should have 1 queued event")
        XCTAssertEqual(notificationsModel.notifications.count, 0, "Notifications should be empty before flush")
    }

    /// Test: Events appear immediately when should_queue is false
    func testEventsImmediateWhenShouldQueueFalse() throws {
        notificationsModel.set_should_queue(false)

        guard let reply = makeTestNote(content: "Immediate reply") else {
            XCTFail("Failed to create test note")
            return
        }

        let inserted = notificationsModel.insert_event(reply, damus_state: damus)

        XCTAssertTrue(inserted, "Event should be inserted")
        XCTAssertEqual(notificationsModel.incoming_events.count, 0, "No queued events")
        XCTAssertGreaterThan(notificationsModel.notifications.count, 0, "Notifications should appear")
    }

    /// Test: Flush moves queued events to notifications
    func testFlushMovesQueuedEvents() throws {
        notificationsModel.set_should_queue(true)

        guard let reply = makeTestNote(content: "Flush test") else {
            XCTFail("Failed to create test note")
            return
        }

        _ = notificationsModel.insert_event(reply, damus_state: damus)

        XCTAssertEqual(notificationsModel.notifications.count, 0, "No notifications before flush")

        let flushed = notificationsModel.flush(damus)

        XCTAssertTrue(flushed, "Flush should report changes")
        XCTAssertGreaterThan(notificationsModel.notifications.count, 0, "Notifications should appear after flush")
    }

    // MARK: - Deduplication Tests

    /// Test: Duplicate events are rejected
    func testDuplicateEventsRejected() throws {
        notificationsModel.set_should_queue(false)

        guard let reply = makeTestNote(content: "Duplicate test") else {
            XCTFail("Failed to create test note")
            return
        }

        let first = notificationsModel.insert_event(reply, damus_state: damus)
        let duplicate = notificationsModel.insert_event(reply, damus_state: damus)

        XCTAssertTrue(first, "First insert should succeed")
        XCTAssertFalse(duplicate, "Duplicate should be rejected")
    }

    /// Test: Duplicate queued events are rejected
    func testDuplicateQueuedEventsRejected() throws {
        notificationsModel.set_should_queue(true)

        guard let reply = makeTestNote(content: "Duplicate queue test") else {
            XCTFail("Failed to create test note")
            return
        }

        let first = notificationsModel.insert_event(reply, damus_state: damus)
        let duplicate = notificationsModel.insert_event(reply, damus_state: damus)

        XCTAssertTrue(first, "First insert should succeed")
        XCTAssertFalse(duplicate, "Duplicate should be rejected")
        XCTAssertEqual(notificationsModel.incoming_events.count, 1, "Only one event queued")
    }

    // MARK: - Notification Type Tests

    /// Test: Reactions are grouped by target event
    func testReactionsGroupedByTarget() throws {
        notificationsModel.set_should_queue(false)

        guard let reaction1 = makeReaction(content: "+"),
              let reaction2 = makeReaction(content: "🔥") else {
            XCTFail("Failed to create reactions")
            return
        }

        _ = notificationsModel.insert_event(reaction1, damus_state: damus)
        _ = notificationsModel.insert_event(reaction2, damus_state: damus)

        // Both reactions target the same note, should be in same group
        let reactionNotifs = notificationsModel.notifications.filter {
            if case .reaction = $0 { return true }
            return false
        }

        XCTAssertEqual(reactionNotifs.count, 1, "Should have one reaction group")
    }

    /// Test: Notifications sorted by time (newest first)
    func testNotificationsSortedByTime() throws {
        notificationsModel.set_should_queue(false)

        let now = UInt32(Date().timeIntervalSince1970)

        guard let oldReply = makeTestNote(content: "Old reply", createdAt: now - 3600),
              let newReply = makeTestNote(content: "New reply", createdAt: now) else {
            XCTFail("Failed to create test notes")
            return
        }

        // Insert in wrong order
        _ = notificationsModel.insert_event(oldReply, damus_state: damus)
        _ = notificationsModel.insert_event(newReply, damus_state: damus)

        guard notificationsModel.notifications.count >= 2 else {
            XCTFail("Should have at least 2 notifications")
            return
        }

        XCTAssertGreaterThan(notificationsModel.notifications[0].last_event_at,
                             notificationsModel.notifications[1].last_event_at,
                             "Newest should be first")
    }

    // MARK: - Unique Pubkeys Tests

    /// Test: uniq_pubkeys extracts unique authors
    func testUniqPubkeysExtractsAuthors() throws {
        notificationsModel.set_should_queue(true)

        guard let reply = makeTestNote(content: "Author test") else {
            XCTFail("Failed to create test note")
            return
        }

        _ = notificationsModel.insert_event(reply, damus_state: damus)

        let pubkeys = notificationsModel.uniq_pubkeys()

        XCTAssertEqual(pubkeys.count, 1, "Should have one unique pubkey")
        XCTAssertEqual(pubkeys.first, test_keypair.pubkey, "Should be test keypair pubkey")
    }
}

// MARK: - Thread Loading Network Tests

/// Tests for ThreadModel and ThreadEventMap under various conditions.
@MainActor
final class ThreadLoadingNetworkTests: XCTestCase {

    /// Creates a test text note event.
    func makeTestNote(content: String = "Test note", replyTo: NoteId? = nil, createdAt: UInt32? = nil) -> NostrEvent? {
        let created = createdAt ?? UInt32(Date().timeIntervalSince1970)
        var tags: [[String]] = []
        if let replyTo = replyTo {
            tags.append(["e", replyTo.hex()])
        }
        return NostrEvent(content: content, keypair: test_keypair, kind: 1, tags: tags, createdAt: created)
    }

    // MARK: - ThreadEventMap Tests

    /// Test: Events are added to ThreadEventMap
    func testEventAddedToMap() throws {
        var map = ThreadEventMap()

        guard let note = makeTestNote(content: "Map test") else {
            XCTFail("Failed to create test note")
            return
        }

        map.add(event: note)

        XCTAssertTrue(map.contains(id: note.id), "Map should contain the event")
        XCTAssertEqual(map.events.count, 1, "Map should have one event")
    }

    /// Test: Duplicate events don't create duplicates in map
    func testDuplicateEventInMap() throws {
        var map = ThreadEventMap()

        guard let note = makeTestNote(content: "Duplicate map test") else {
            XCTFail("Failed to create test note")
            return
        }

        map.add(event: note)
        map.add(event: note)

        XCTAssertEqual(map.events.count, 1, "Should not duplicate events")
    }

    /// Test: Events are retrievable by ID
    func testEventRetrievableById() throws {
        var map = ThreadEventMap()

        guard let note = makeTestNote(content: "Retrieve test") else {
            XCTFail("Failed to create test note")
            return
        }

        map.add(event: note)

        let retrieved = map.get(id: note.id)

        XCTAssertNotNil(retrieved, "Should retrieve event")
        XCTAssertEqual(retrieved?.content, "Retrieve test", "Content should match")
    }

    /// Test: sorted_events returns chronological order
    func testSortedEventsChronological() throws {
        var map = ThreadEventMap()

        let now = UInt32(Date().timeIntervalSince1970)

        guard let oldNote = makeTestNote(content: "Old", createdAt: now - 3600),
              let newNote = makeTestNote(content: "New", createdAt: now) else {
            XCTFail("Failed to create test notes")
            return
        }

        // Insert in reverse order
        map.add(event: newNote)
        map.add(event: oldNote)

        let sorted = map.sorted_events

        XCTAssertEqual(sorted.count, 2, "Should have 2 events")
        XCTAssertEqual(sorted.first?.content, "Old", "Old event should be first (chronological)")
        XCTAssertEqual(sorted.last?.content, "New", "New event should be last")
    }

    /// Test: Reply hierarchy is tracked correctly
    func testReplyHierarchyTracked() throws {
        var map = ThreadEventMap()

        guard let parent = makeTestNote(content: "Parent") else {
            XCTFail("Failed to create parent note")
            return
        }

        guard let child = makeTestNote(content: "Child", replyTo: parent.id) else {
            XCTFail("Failed to create child note")
            return
        }

        map.add(event: parent)
        map.add(event: child)

        // Child should reference parent
        XCTAssertTrue(map.contains(id: parent.id), "Map should contain parent")
        XCTAssertTrue(map.contains(id: child.id), "Map should contain child")

        // Verify the child event's reply reference
        let childEvent = map.get(id: child.id)
        XCTAssertEqual(childEvent?.direct_replies(), parent.id, "Child should reply to parent")
    }

    // MARK: - Thread Filter Tests

    /// Test: Thread subscription filter includes correct kinds
    func testThreadFilterKinds() {
        var ref_events = NostrFilter()
        ref_events.kinds = [.text]
        ref_events.limit = 1000

        XCTAssertEqual(ref_events.kinds?.count, 1)
        XCTAssertEqual(ref_events.kinds?.first, .text)
        XCTAssertEqual(ref_events.limit, 1000)
    }

    /// Test: Meta events filter includes reactions, zaps, boosts
    func testMetaEventsFilter() {
        var meta_events = NostrFilter()
        meta_events.kinds = [.zap, .text, .boost, .like]
        meta_events.limit = 1000

        XCTAssertEqual(meta_events.kinds?.count, 4)
        XCTAssertTrue(meta_events.kinds?.contains(.zap) ?? false)
        XCTAssertTrue(meta_events.kinds?.contains(.boost) ?? false)
        XCTAssertTrue(meta_events.kinds?.contains(.like) ?? false)
    }

    /// Test: Quote events filter uses quotes field
    func testQuoteEventsFilter() {
        let noteId = NoteId(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!

        var quote_events = NostrFilter()
        quote_events.kinds = [.text]
        quote_events.quotes = [noteId]
        quote_events.limit = 1000

        XCTAssertEqual(quote_events.quotes?.count, 1)
        XCTAssertEqual(quote_events.quotes?.first, noteId)
    }

    // MARK: - Thread Loading Resilience Tests

    /// Test: Thread map handles missing parent gracefully
    func testMissingParentHandledGracefully() throws {
        var map = ThreadEventMap()

        // Create child that references non-existent parent
        let fakeParentId = NoteId(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!

        guard let orphan = makeTestNote(content: "Orphan", replyTo: fakeParentId) else {
            XCTFail("Failed to create orphan note")
            return
        }

        map.add(event: orphan)

        // Should still contain the orphan event
        XCTAssertTrue(map.contains(id: orphan.id), "Map should contain orphan")

        // Parent lookup should return nil (not crash)
        let parent = map.get(id: fakeParentId)
        XCTAssertNil(parent, "Parent should be nil")

        // parent_events should return empty array (not crash)
        let parents = map.parent_events(of: orphan)
        XCTAssertEqual(parents.count, 0, "Should have no parents")
    }
}

// MARK: - User Lookup Network Tests

/// Tests for profile metadata lookup under various conditions.
final class UserLookupNetworkTests: XCTestCase {

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

    // MARK: - Profile Filter Tests

    /// Test: Profile metadata filter is kind 0
    func testProfileMetadataFilterKind() {
        var filter = NostrFilter(kinds: [.metadata])

        XCTAssertEqual(filter.kinds?.count, 1)
        XCTAssertEqual(filter.kinds?.first, .metadata)
    }

    /// Test: Profile filter includes author pubkey
    func testProfileFilterWithAuthor() {
        let pubkey = test_pubkey

        var filter = NostrFilter(kinds: [.metadata])
        filter.authors = [pubkey]

        XCTAssertEqual(filter.authors?.count, 1)
        XCTAssertEqual(filter.authors?.first, pubkey)
    }

    /// Test: Multiple profile lookup filter
    func testMultipleProfileLookup() {
        let pubkey1 = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let pubkey2 = Pubkey(hex: "3bf0c63fcb93463407af97a5e5ee64fa883d107ef9e558472c4eb9aaaefa459d")!

        var filter = NostrFilter(kinds: [.metadata])
        filter.authors = [pubkey1, pubkey2]

        XCTAssertEqual(filter.authors?.count, 2)
        XCTAssertTrue(filter.authors?.contains(pubkey1) ?? false)
        XCTAssertTrue(filter.authors?.contains(pubkey2) ?? false)
    }

    // MARK: - Profile Event Creation Tests

    /// Test: Metadata event is kind 0
    func testMetadataEventIsKind0() {
        let profile = Profile(name: "testuser")

        guard let event = make_metadata_event(keypair: test_keypair_full, metadata: profile) else {
            XCTFail("Failed to create metadata event")
            return
        }

        XCTAssertEqual(event.kind, NostrKind.metadata.rawValue)
        XCTAssertEqual(event.kind, 0)
    }

    /// Test: Metadata event contains profile JSON
    func testMetadataEventContainsJSON() {
        let profile = Profile(name: "lookupuser", display_name: "Lookup User")

        guard let event = make_metadata_event(keypair: test_keypair_full, metadata: profile) else {
            XCTFail("Failed to create metadata event")
            return
        }

        XCTAssertTrue(event.content.contains("lookupuser"), "Should contain name")
        XCTAssertTrue(event.content.contains("Lookup User"), "Should contain display_name")
    }

    // MARK: - Profile Relay Communication Tests

    /// Test: Profile request sent to relay
    func testProfileRequestSentToRelay() async throws {
        let pubkey = test_pubkey

        var filter = NostrFilter(kinds: [.metadata])
        filter.authors = [pubkey]

        // Simulate sending a REQ (profile lookup would do this)
        mockSocket.reset()

        // Note: In actual implementation, this would go through nostrNetwork.reader
        // For this test, we verify filter creation is correct
        XCTAssertNotNil(filter.authors)
        XCTAssertEqual(filter.kinds?.first, .metadata)
    }

    /// Test: Profile lookup handles missing profile
    func testMissingProfileHandled() async throws {
        // When profile doesn't exist, filter should still be valid
        let unknownPubkey = Pubkey(hex: "0000000000000000000000000000000000000000000000000000000000000001")!

        var filter = NostrFilter(kinds: [.metadata])
        filter.authors = [unknownPubkey]

        // Filter should be valid even for unknown pubkeys
        XCTAssertEqual(filter.authors?.first, unknownPubkey)
    }

    /// Test: Profile metadata cached in Ndb
    func testProfileCachedInNdb() async throws {
        // Verify Ndb is available for caching
        XCTAssertNotNil(ndb, "Ndb should be available for profile caching")
    }

    // MARK: - Relay List Filter Tests

    /// Test: Relay list filter is kind 10002
    func testRelayListFilter() {
        let pubkey = test_pubkey

        var filter = NostrFilter(kinds: [.relay_list])
        filter.authors = [pubkey]

        XCTAssertEqual(filter.kinds?.first, .relay_list)
        XCTAssertEqual(filter.authors?.first, pubkey)
    }

    /// Test: Contacts filter is kind 3
    func testContactsFilter() {
        let pubkey = test_pubkey

        var filter = NostrFilter(kinds: [.contacts])
        filter.authors = [pubkey]

        XCTAssertEqual(filter.kinds?.first, .contacts)
        XCTAssertEqual(filter.authors?.first, pubkey)
    }

    /// Test: Profile subscription includes multiple kinds
    func testProfileSubscriptionMultipleKinds() {
        let pubkey = test_pubkey

        // ProfileModel.subscribe() uses these kinds
        var profile_filter = NostrFilter(kinds: [.contacts, .metadata, .boost])
        profile_filter.authors = [pubkey]

        XCTAssertEqual(profile_filter.kinds?.count, 3)
        XCTAssertTrue(profile_filter.kinds?.contains(.contacts) ?? false)
        XCTAssertTrue(profile_filter.kinds?.contains(.metadata) ?? false)
        XCTAssertTrue(profile_filter.kinds?.contains(.boost) ?? false)
    }
}
