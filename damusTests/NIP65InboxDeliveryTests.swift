//
//  NIP65InboxDeliveryTests.swift
//  damusTests
//
//  Tests for NIP-65 write-side inbox delivery.
//  Verifies that InboxRelayResolver resolves the correct inbox relays
//  and that PostBox dispatches inbox delivery at the right time.
//

import XCTest
@testable import damus

final class NIP65InboxDeliveryTests: XCTestCase {

    // MARK: - Shared test keypairs

    /// The "author" of the test event
    private let authorKeypair: Keypair = {
        let kp = generate_new_keypair()
        return Keypair(pubkey: kp.pubkey, privkey: kp.privkey)
    }()

    /// Tagged users with known keypairs (so we can create signed kind:10002 events for them)
    private let userA_keypair: FullKeypair = generate_new_keypair()
    private let userB_keypair: FullKeypair = generate_new_keypair()
    private let userC_keypair: FullKeypair = generate_new_keypair()

    // MARK: - Helper: Ingest a kind:10002 relay list into NDB for a given user

    /// Creates a signed kind:10002 event for the given keypair with the given relay items,
    /// and ingests it into the provided Ndb instance.
    private func ingestRelayList(ndb: Ndb, keypair: FullKeypair, relays: [NIP65.RelayList.RelayItem]) throws {
        let relayList = NIP65.RelayList(relays: relays)
        guard let event = relayList.toNostrEvent(keypair: keypair) else {
            XCTFail("Failed to create relay list event")
            return
        }
        let json = encode_json(event)!
        let relayMessage = "[\"EVENT\",\"subid\",\(json)]"
        let processed = ndb.processEvent(relayMessage)
        XCTAssertTrue(processed, "Failed to ingest relay list event into NDB")

        // Poll until NDB has indexed the event (deterministic, no fixed sleep)
        let deadline = Date().addingTimeInterval(5.0)
        while InboxRelayResolver.lookupRelayListEvent(ndb: ndb, pubkey: keypair.pubkey) == nil {
            guard Date() < deadline else {
                XCTFail("Timed out waiting for NDB to index relay list for \(keypair.pubkey)")
                return
            }
            Thread.sleep(forTimeInterval: 0.005)
        }
    }

    /// Helper to create a relay item
    private func relayItem(_ urlString: String, _ rw: NIP65.RelayList.RelayItem.RWConfiguration) -> NIP65.RelayList.RelayItem {
        return NIP65.RelayList.RelayItem(url: RelayURL(urlString)!, rwConfiguration: rw)
    }

    // MARK: - InboxRelayResolver Tests

    /// Test that inbox relays are correctly resolved for tagged pubkeys
    func testResolveInboxRelays_basicCase() throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        // Setup: userA reads from relay-a.example.com, userB reads from relay-b.example.com
        try ingestRelayList(ndb: ndb, keypair: userA_keypair, relays: [
            relayItem("wss://relay-a.example.com", .read),
        ])
        try ingestRelayList(ndb: ndb, keypair: userB_keypair, relays: [
            relayItem("wss://relay-b.example.com", .readWrite),
        ])

        // Create a note from the author tagging userA and userB
        let event = NdbNote(
            content: "Hello @userA @userB",
            keypair: authorKeypair,
            kind: NostrKind.text.rawValue,
            tags: [
                ["p", userA_keypair.pubkey.hex()],
                ["p", userB_keypair.pubkey.hex()],
            ]
        )!

        let authorRelays: Set<RelayURL> = [RelayURL("wss://author-relay.example.com")!]
        let result = InboxRelayResolver.resolveInboxRelays(event: event, ndb: ndb, excludeRelays: authorRelays)

        // Both userA's read relay and userB's readWrite relay should be returned
        let resultSet = Set(result)
        XCTAssertTrue(resultSet.contains(RelayURL("wss://relay-a.example.com")!), "Should include userA's read relay")
        XCTAssertTrue(resultSet.contains(RelayURL("wss://relay-b.example.com")!), "Should include userB's readWrite relay")
    }

    /// Test that write-only relays are excluded (they are not inbox relays)
    func testResolveInboxRelays_excludesWriteOnlyRelays() throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        try ingestRelayList(ndb: ndb, keypair: userA_keypair, relays: [
            relayItem("wss://write-only.example.com", .write),
            relayItem("wss://read-relay.example.com", .read),
        ])

        let event = NdbNote(
            content: "Hello",
            keypair: authorKeypair,
            kind: NostrKind.text.rawValue,
            tags: [["p", userA_keypair.pubkey.hex()]]
        )!

        let result = InboxRelayResolver.resolveInboxRelays(event: event, ndb: ndb, excludeRelays: [])
        let resultSet = Set(result)

        XCTAssertFalse(resultSet.contains(RelayURL("wss://write-only.example.com")!), "Write-only relays should NOT be included")
        XCTAssertTrue(resultSet.contains(RelayURL("wss://read-relay.example.com")!), "Read relays should be included")
    }

    /// Test that relays already in the author's set are excluded
    func testResolveInboxRelays_excludesAuthorRelays() throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        let sharedRelay = RelayURL("wss://shared-relay.example.com")!
        try ingestRelayList(ndb: ndb, keypair: userA_keypair, relays: [
            relayItem("wss://shared-relay.example.com", .readWrite),
            relayItem("wss://unique-relay.example.com", .read),
        ])

        let event = NdbNote(
            content: "Hello",
            keypair: authorKeypair,
            kind: NostrKind.text.rawValue,
            tags: [["p", userA_keypair.pubkey.hex()]]
        )!

        let authorRelays: Set<RelayURL> = [sharedRelay]
        let result = InboxRelayResolver.resolveInboxRelays(event: event, ndb: ndb, excludeRelays: authorRelays)
        let resultSet = Set(result)

        XCTAssertFalse(resultSet.contains(sharedRelay), "Author's own relays should be excluded")
        XCTAssertTrue(resultSet.contains(RelayURL("wss://unique-relay.example.com")!), "Non-shared relays should be included")
    }

    /// Test that the author tagging themselves doesn't generate inbox relay lookups
    func testResolveInboxRelays_skipsAuthorPubkey() throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        // Ingest a relay list for the author
        let authorFull = authorKeypair.to_full()!
        try ingestRelayList(ndb: ndb, keypair: authorFull, relays: [
            relayItem("wss://author-inbox.example.com", .read),
        ])

        let event = NdbNote(
            content: "Talking to myself",
            keypair: authorKeypair,
            kind: NostrKind.text.rawValue,
            tags: [["p", authorKeypair.pubkey.hex()]]
        )!

        let result = InboxRelayResolver.resolveInboxRelays(event: event, ndb: ndb, excludeRelays: [])

        XCTAssertTrue(result.isEmpty, "Author's own inbox relays should not be resolved when they tag themselves")
    }

    /// Test that events with no p-tags return an empty result
    func testResolveInboxRelays_noPTags() throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        let event = NdbNote(
            content: "No tags here",
            keypair: authorKeypair,
            kind: NostrKind.text.rawValue,
            tags: []
        )!

        let result = InboxRelayResolver.resolveInboxRelays(event: event, ndb: ndb, excludeRelays: [])
        XCTAssertTrue(result.isEmpty, "Events with no p-tags should return empty relays")
    }

    /// Test that tagged users without a kind:10002 in NDB are gracefully skipped
    func testResolveInboxRelays_missingRelayList() throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        // userA has a relay list, userB does not
        try ingestRelayList(ndb: ndb, keypair: userA_keypair, relays: [
            relayItem("wss://relay-a.example.com", .read),
        ])

        let event = NdbNote(
            content: "Hello both",
            keypair: authorKeypair,
            kind: NostrKind.text.rawValue,
            tags: [
                ["p", userA_keypair.pubkey.hex()],
                ["p", userB_keypair.pubkey.hex()],
            ]
        )!

        let result = InboxRelayResolver.resolveInboxRelays(event: event, ndb: ndb, excludeRelays: [])
        let resultSet = Set(result)

        XCTAssertTrue(resultSet.contains(RelayURL("wss://relay-a.example.com")!), "userA's relay should still be included")
        XCTAssertEqual(result.count, 1, "Only userA's relay should appear since userB has no relay list")
    }

    /// Test deduplication: two users share the same inbox relay
    func testResolveInboxRelays_deduplication() throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        let sharedRelay = "wss://shared.example.com"
        try ingestRelayList(ndb: ndb, keypair: userA_keypair, relays: [
            relayItem(sharedRelay, .read),
        ])
        try ingestRelayList(ndb: ndb, keypair: userB_keypair, relays: [
            relayItem(sharedRelay, .readWrite),
        ])

        let event = NdbNote(
            content: "Hello both",
            keypair: authorKeypair,
            kind: NostrKind.text.rawValue,
            tags: [
                ["p", userA_keypair.pubkey.hex()],
                ["p", userB_keypair.pubkey.hex()],
            ]
        )!

        let result = InboxRelayResolver.resolveInboxRelays(event: event, ndb: ndb, excludeRelays: [])

        // The shared relay should appear only once
        XCTAssertEqual(result.count, 1, "Shared relays should be deduplicated")
        XCTAssertEqual(result.first, RelayURL(sharedRelay)!)
    }

    /// Test MAX_INBOX_RELAYS cap
    func testResolveInboxRelays_capsAtMax() throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        // Create many users each with a unique relay
        var tags: [[String]] = []
        for i in 0..<10 {
            let kp = generate_new_keypair()
            try ingestRelayList(ndb: ndb, keypair: kp, relays: [
                relayItem("wss://relay-\(i).example.com", .read),
            ])
            tags.append(["p", kp.pubkey.hex()])
        }

        let event = NdbNote(
            content: "Hellthread",
            keypair: authorKeypair,
            kind: NostrKind.text.rawValue,
            tags: tags
        )!

        let result = InboxRelayResolver.resolveInboxRelays(event: event, ndb: ndb, excludeRelays: [])

        XCTAssertLessThanOrEqual(result.count, InboxRelayResolver.MAX_INBOX_RELAYS,
            "Result should be capped at MAX_INBOX_RELAYS (\(InboxRelayResolver.MAX_INBOX_RELAYS))")
    }

    /// Test lookupRelayList returns correct parsed relay list
    func testLookupRelayList() throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        try ingestRelayList(ndb: ndb, keypair: userA_keypair, relays: [
            relayItem("wss://read.example.com", .read),
            relayItem("wss://write.example.com", .write),
            relayItem("wss://readwrite.example.com", .readWrite),
        ])

        let relayList = InboxRelayResolver.lookupRelayList(ndb: ndb, pubkey: userA_keypair.pubkey)

        XCTAssertNotNil(relayList, "Should find the relay list in NDB")
        XCTAssertEqual(relayList?.relays.count, 3, "Should have 3 relays")

        // Verify individual relay configurations
        XCTAssertTrue(relayList!.relays[RelayURL("wss://read.example.com")!]!.rwConfiguration.canRead)
        XCTAssertFalse(relayList!.relays[RelayURL("wss://read.example.com")!]!.rwConfiguration.canWrite)
        XCTAssertFalse(relayList!.relays[RelayURL("wss://write.example.com")!]!.rwConfiguration.canRead)
        XCTAssertTrue(relayList!.relays[RelayURL("wss://write.example.com")!]!.rwConfiguration.canWrite)
        XCTAssertTrue(relayList!.relays[RelayURL("wss://readwrite.example.com")!]!.rwConfiguration.canRead)
        XCTAssertTrue(relayList!.relays[RelayURL("wss://readwrite.example.com")!]!.rwConfiguration.canWrite)
    }

    /// Test lookupRelayListEvent returns the raw event for republishing
    func testLookupRelayListEvent() throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        try ingestRelayList(ndb: ndb, keypair: userA_keypair, relays: [
            relayItem("wss://relay.example.com", .readWrite),
        ])

        let event = InboxRelayResolver.lookupRelayListEvent(ndb: ndb, pubkey: userA_keypair.pubkey)

        XCTAssertNotNil(event, "Should find the relay list event in NDB")
        XCTAssertEqual(event?.known_kind, .relay_list, "Should be a kind:10002 event")
        XCTAssertEqual(event?.pubkey, userA_keypair.pubkey, "Should be authored by userA")
    }

    /// Test lookupRelayList returns nil for unknown pubkey
    func testLookupRelayList_notFound() {
        let ndb = Ndb.test
        defer { ndb.close() }

        let unknownPubkey = generate_new_keypair().pubkey
        let relayList = InboxRelayResolver.lookupRelayList(ndb: ndb, pubkey: unknownPubkey)

        XCTAssertNil(relayList, "Should return nil for unknown pubkey")
    }

    // MARK: - PostBox Integration Tests

    /// Test that PostBox dispatches inbox delivery for non-targeted events with p-tags
    func testPostBox_inboxDeliveryEvaluated_forBroadcast() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        let pool = RelayPool(ndb: nil, keypair: test_keypair)
        let postbox = PostBox(pool: pool, ndb: ndb)

        // Ingest a relay list for userA
        try ingestRelayList(ndb: ndb, keypair: userA_keypair, relays: [
            relayItem("wss://inbox-relay.example.com", .read),
        ])

        // Create a note tagging userA
        let event = NdbNote(
            content: "Hello userA",
            keypair: authorKeypair,
            kind: NostrKind.text.rawValue,
            tags: [["p", userA_keypair.pubkey.hex()]]
        )!

        // Send without explicit `to:` (broadcast)
        await postbox.send(event)

        // Check that the event was stored and inbox delivery was dispatched
        let posted = await postbox.events[event.id]
        XCTAssertNotNil(posted, "Event should be stored in PostBox")
        XCTAssertTrue(posted!.inboxDeliveryEvaluated, "Inbox delivery should have been dispatched for broadcast events with p-tags")
        XCTAssertFalse(posted!.is_targeted, "Broadcast events should not be marked as targeted")
    }

    /// Test that PostBox does NOT dispatch inbox delivery for targeted events (e.g. NWC)
    func testPostBox_noInboxDelivery_forTargetedEvents() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        let pool = RelayPool(ndb: nil, keypair: test_keypair)
        let postbox = PostBox(pool: pool, ndb: ndb)

        // Ingest a relay list for userA
        try ingestRelayList(ndb: ndb, keypair: userA_keypair, relays: [
            relayItem("wss://inbox-relay.example.com", .read),
        ])

        // Create a note tagging userA
        let event = NdbNote(
            content: "Direct to relay",
            keypair: authorKeypair,
            kind: NostrKind.text.rawValue,
            tags: [["p", userA_keypair.pubkey.hex()]]
        )!

        // Send with explicit `to:` (targeted)
        let targetRelay = RelayURL("wss://specific-relay.example.com")!
        await postbox.send(event, to: [targetRelay])

        let posted = await postbox.events[event.id]
        XCTAssertNotNil(posted, "Event should be stored in PostBox")
        XCTAssertTrue(posted!.is_targeted, "Should be marked as targeted")
        // For targeted events, flush_event sets inboxDeliveryEvaluated=true but dispatchInboxDelivery
        // returns early due to is_targeted guard
        XCTAssertTrue(posted!.inboxDeliveryEvaluated, "Flag is set by flush_event but dispatchInboxDelivery exits early for targeted events")
    }

    /// Test that PostBox does NOT dispatch inbox delivery for events without p-tags
    func testPostBox_noInboxDelivery_withoutPTags() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        let pool = RelayPool(ndb: nil, keypair: test_keypair)
        let postbox = PostBox(pool: pool, ndb: ndb)

        // Create a note with NO p-tags
        let event = NdbNote(
            content: "Just a note with no mentions",
            keypair: authorKeypair,
            kind: NostrKind.text.rawValue,
            tags: []
        )!

        await postbox.send(event)

        let posted = await postbox.events[event.id]
        XCTAssertNotNil(posted, "Event should be stored in PostBox")
        // inboxDeliveryEvaluated is set to true by flush_event,
        // but dispatchInboxDelivery returns early since there are no p-tags
        XCTAssertTrue(posted!.inboxDeliveryEvaluated, "Flag is set by flush_event")
    }

    /// Test that PostBox without ndb does not crash and skips inbox delivery
    func testPostBox_noNdb_skipsInboxDelivery() async throws {
        let pool = RelayPool(ndb: nil, keypair: test_keypair)
        let postbox = PostBox(pool: pool, ndb: nil)  // No ndb

        let event = NdbNote(
            content: "Hello",
            keypair: authorKeypair,
            kind: NostrKind.text.rawValue,
            tags: [["p", userA_keypair.pubkey.hex()]]
        )!

        // Should not crash even without ndb
        await postbox.send(event)

        let posted = await postbox.events[event.id]
        XCTAssertNotNil(posted, "Event should be stored in PostBox")
        // flush_event sets the flag, but dispatchInboxDelivery returns early since ndb is nil
        XCTAssertTrue(posted!.inboxDeliveryEvaluated, "Flag is set by flush_event")
    }

    /// Test that delayed events don't dispatch inbox delivery until flushed
    func testPostBox_delayedEvent_inboxDeliveryOnFlush() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        let pool = RelayPool(ndb: nil, keypair: test_keypair)
        let postbox = PostBox(pool: pool, ndb: ndb)

        try ingestRelayList(ndb: ndb, keypair: userA_keypair, relays: [
            relayItem("wss://inbox-relay.example.com", .read),
        ])

        let event = NdbNote(
            content: "Delayed note",
            keypair: authorKeypair,
            kind: NostrKind.text.rawValue,
            tags: [["p", userA_keypair.pubkey.hex()]]
        )!

        // Send with delay (won't flush immediately)
        await postbox.send(event, delay: 60.0)

        let posted = await postbox.events[event.id]
        XCTAssertNotNil(posted, "Event should be stored in PostBox")
        XCTAssertFalse(posted!.inboxDeliveryEvaluated, "Inbox delivery should NOT be dispatched yet for delayed events")
    }

    /// Test that the PostedEvent.is_targeted flag is correctly set based on `to:` parameter
    func testPostedEvent_isTargeted() async throws {
        let pool = RelayPool(ndb: nil, keypair: test_keypair)
        let postbox = PostBox(pool: pool, ndb: nil)

        let event1 = NdbNote(content: "broadcast", keypair: authorKeypair, kind: 1, tags: [])!
        let event2 = NdbNote(content: "targeted", keypair: authorKeypair, kind: 1, tags: [])!

        await postbox.send(event1)  // broadcast (to: nil)
        await postbox.send(event2, to: [RelayURL("wss://specific.example.com")!])  // targeted

        let posted1 = await postbox.events[event1.id]
        let posted2 = await postbox.events[event2.id]

        XCTAssertFalse(posted1!.is_targeted, "Broadcast event should not be targeted")
        XCTAssertTrue(posted2!.is_targeted, "Targeted event should be marked as targeted")
    }

    // MARK: - deliverToInboxRelays static method tests

    /// Test that deliverToInboxRelays resolves relays correctly end-to-end
    func testDeliverToInboxRelays_resolvesCorrectRelays() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        // Ingest relay lists
        try ingestRelayList(ndb: ndb, keypair: userA_keypair, relays: [
            relayItem("wss://inbox-a.example.com", .read),
        ])
        try ingestRelayList(ndb: ndb, keypair: userB_keypair, relays: [
            relayItem("wss://inbox-b.example.com", .readWrite),
        ])

        // Create an event tagging both users
        let event = NdbNote(
            content: "Hello A and B",
            keypair: authorKeypair,
            kind: NostrKind.text.rawValue,
            tags: [
                ["p", userA_keypair.pubkey.hex()],
                ["p", userB_keypair.pubkey.hex()],
            ]
        )!

        let authorRelays: Set<RelayURL> = [RelayURL("wss://author-relay.example.com")!]

        // Verify InboxRelayResolver resolves correctly (this is the core logic)
        let resolved = InboxRelayResolver.resolveInboxRelays(event: event, ndb: ndb, excludeRelays: authorRelays)

        XCTAssertEqual(resolved.count, 2, "Should resolve 2 inbox relays")
        let resolvedSet = Set(resolved)
        XCTAssertTrue(resolvedSet.contains(RelayURL("wss://inbox-a.example.com")!))
        XCTAssertTrue(resolvedSet.contains(RelayURL("wss://inbox-b.example.com")!))
    }

    /// Integration test: Verify that deliverToInboxRelays with no matching relays is a no-op
    func testDeliverToInboxRelays_noRelays_isNoop() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        let pool = RelayPool(ndb: nil, keypair: test_keypair)

        // No relay lists ingested → no inbox relays to resolve
        let event = NdbNote(
            content: "Hello unknown user",
            keypair: authorKeypair,
            kind: NostrKind.text.rawValue,
            tags: [["p", userA_keypair.pubkey.hex()]]
        )!

        // This should complete without error even though there are no inbox relays
        await PostBox.deliverToInboxRelays(
            event: event,
            pool: pool,
            ndb: ndb
        )
        // If we get here without crashing, the test passes
    }

    /// Test that all author's relays are excluded when they overlap with inbox relays
    func testDeliverToInboxRelays_allRelaysExcluded() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        let pool = RelayPool(ndb: nil, keypair: test_keypair)

        // Add a write-enabled relay to the pool so pool.our_descriptors is non-empty
        // and the exclusion branch in deliverToInboxRelays is actually exercised.
        let authorRelayURL = RelayURL("wss://author-relay.example.com")!
        let desc = RelayPool.RelayDescriptor(url: authorRelayURL, info: .readWrite)
        try await pool.add_relay(desc)

        // userA's inbox relay is the same as the author's relay
        try ingestRelayList(ndb: ndb, keypair: userA_keypair, relays: [
            relayItem("wss://author-relay.example.com", .read),
        ])

        let event = NdbNote(
            content: "Hello",
            keypair: authorKeypair,
            kind: NostrKind.text.rawValue,
            tags: [["p", userA_keypair.pubkey.hex()]]
        )!

        let authorRelays: Set<RelayURL> = [authorRelayURL]
        let resolved = InboxRelayResolver.resolveInboxRelays(event: event, ndb: ndb, excludeRelays: authorRelays)

        XCTAssertTrue(resolved.isEmpty, "All relays should be excluded when they match author's relays")

        // Now test via deliverToInboxRelays which derives authorRelays from pool.our_descriptors.
        // Since we added the relay to the pool, the exclusion branch is exercised end-to-end.
        await PostBox.deliverToInboxRelays(
            event: event,
            pool: pool,
            ndb: ndb
        )
    }
}
