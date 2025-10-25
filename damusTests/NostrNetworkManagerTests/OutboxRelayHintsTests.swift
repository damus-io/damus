//
//  OutboxRelayHintsTests.swift
//  damusTests
//
//  Created by OpenAI Codex on 2025-09-06.
//

import XCTest
@testable import damus

final class OutboxRelayHintsTests: XCTestCase {
    var ndb: Ndb!
    var hints: OutboxRelayHints!
    let author = test_keypair.pubkey
    
    override func setUp() {
        super.setUp()
        ndb = .test
        hints = OutboxRelayHints(ndb: ndb, cacheTTL: 60)
    }
    
    override func tearDown() {
        ndb?.close()
        ndb = nil
        hints = nil
        super.tearDown()
    }
    
    func testLoadsLatestReadableRelays() async throws {
        ingestRelayList(
            [
                makeRelayItem("wss://relay.old-1.example"),
                makeRelayItem("wss://relay.writeonly.example", .write)
            ],
            createdAt: 100
        )
        
        let relays = await hints.relayURLs(for: [author])[author]
        XCTAssertEqual(relays, [RelayURL("wss://relay.old-1.example")!])
    }
    
    func testPrefersNewestRelayList() async throws {
        ingestRelayList([makeRelayItem("wss://relay.old.example")], createdAt: 10)
        ingestRelayList([makeRelayItem("wss://relay.newer.example")], createdAt: 20)
        
        let relays = await hints.relayURLs(for: [author])[author]
        XCTAssertEqual(relays, [RelayURL("wss://relay.newer.example")!])
    }
    
    func testCacheInvalidationRefreshesResults() async throws {
        ingestRelayList([makeRelayItem("wss://relay.initial.example")], createdAt: 10)
        _ = await hints.relayURLs(for: [author])
        
        ingestRelayList([makeRelayItem("wss://relay.updated.example")], createdAt: 20)
        var relays = await hints.relayURLs(for: [author])[author]
        XCTAssertEqual(relays, [RelayURL("wss://relay.initial.example")!], "Should still serve cached value before invalidation")
        
        await hints.invalidate(pubkeys: [author])
        relays = await hints.relayURLs(for: [author])[author]
        XCTAssertEqual(relays, [RelayURL("wss://relay.updated.example")!])
    }
    
    func testCacheExpiresAfterTTL() async throws {
        hints = OutboxRelayHints(ndb: ndb, cacheTTL: 0.05)
        ingestRelayList([makeRelayItem("wss://relay.old.example")], createdAt: 1)
        _ = await hints.relayURLs(for: [author])
        
        ingestRelayList([makeRelayItem("wss://relay.new.example")], createdAt: 2)
        try await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        
        let relays = await hints.relayURLs(for: [author])[author]
        XCTAssertEqual(relays, [RelayURL("wss://relay.new.example")!])
    }
}

private extension OutboxRelayHintsTests {
    func ingestRelayList(_ relayItems: [NIP65.RelayList.RelayItem], createdAt: UInt32) {
        let relayList = NIP65.RelayList(relays: relayItems)
        guard let event = relayList.toNostrEvent(keypair: test_keypair_full, timestamp: createdAt) else {
            XCTFail("Unable to build relay list event")
            return
        }
        guard let encoded = encode_json(event) else {
            XCTFail("Unable to encode relay list event")
            return
        }
        XCTAssertTrue(
            ndb.process_client_event("[\"EVENT\",\(encoded)]"),
            "Failed to insert relay list into the temporary database"
        )
    }
    
    func makeRelayItem(
        _ urlString: String,
        _ configuration: NIP65.RelayList.RelayItem.RWConfiguration = .readWrite
    ) -> NIP65.RelayList.RelayItem {
        return NIP65.RelayList.RelayItem(
            url: RelayURL(urlString)!,
            rwConfiguration: configuration
        )
    }
}
