//
//  RelayPoolTests.swift
//  damusTests
//
//  Created by Bryan Montz on 2/25/23.
//

import XCTest
@testable import damus

final class RelayPoolTests: XCTestCase {
    
    private let fakeRelayURL = URL(string: "wss://some.relay.com")!
    
    private func setUpPool() throws -> RelayPool {
        let pool = RelayPool()
        XCTAssertTrue(pool.relays.isEmpty)
        
        try pool.add_relay(fakeRelayURL, info: RelayInfo.rw)
        return pool
    }
    
    // MARK: - Relay Add/Remove
    
    func testAddRelay() throws {
        let pool = try setUpPool()
        
        XCTAssertEqual(pool.relays.count, 1)
    }
    
    func testRejectDuplicateRelay() throws {
        let pool = try setUpPool()
        
        XCTAssertThrowsError(try pool.add_relay(fakeRelayURL, info: RelayInfo.rw)) { error in
            XCTAssertEqual(error as? RelayError, RelayError.RelayAlreadyExists)
        }
    }
    
    func testRemoveRelay() throws {
        let pool = try setUpPool()
        
        XCTAssertEqual(pool.relays.count, 1)
        
        pool.remove_relay(fakeRelayURL.absoluteString)
        
        XCTAssertTrue(pool.relays.isEmpty)
    }
    
    func testMarkRelayBroken() throws {
        let pool = try setUpPool()
        
        let relay = try XCTUnwrap(pool.relays.first(where: { $0.id == fakeRelayURL.absoluteString }))
        XCTAssertFalse(relay.is_broken)
        
        pool.mark_broken(fakeRelayURL.absoluteString)
        XCTAssertTrue(relay.is_broken)
    }
    
    func testGetRelay() throws {
        let pool = try setUpPool()
        XCTAssertNotNil(pool.get_relay(fakeRelayURL.absoluteString))
    }
    
    func testGetRelays() throws {
        let pool = try setUpPool()
        
        try pool.add_relay(URL(string: "wss://second.relay.com")!, info: RelayInfo.rw)
        
        let allRelays = pool.get_relays([fakeRelayURL.absoluteString, "wss://second.relay.com"])
        XCTAssertEqual(allRelays.count, 2)
        
        let relays = pool.get_relays(["wss://second.relay.com"])
        XCTAssertEqual(relays.count, 1)
    }
    
    // MARK: - Handler Add/Remove
    
    private func setUpPoolWithHandler(sub_id: String) -> RelayPool {
        let pool = RelayPool()
        XCTAssertTrue(pool.handlers.isEmpty)
        
        pool.register_handler(sub_id: sub_id) { _, _ in }
        return pool
    }
    
    func testAddHandler() {
        let sub_id = "123"
        let pool = setUpPoolWithHandler(sub_id: sub_id)
        
        XCTAssertEqual(pool.handlers.count, 1)
    }
    
    func testRejectDuplicateHandler() {
        let sub_id = "123"
        let pool = setUpPoolWithHandler(sub_id: sub_id)
        XCTAssertEqual(pool.handlers.count, 1)
        
        pool.register_handler(sub_id: sub_id) { _, _ in }
        
        XCTAssertEqual(pool.handlers.count, 1)
    }
    
    func testRemoveHandler() {
        let sub_id = "123"
        let pool = setUpPoolWithHandler(sub_id: sub_id)
        XCTAssertEqual(pool.handlers.count, 1)
        pool.remove_handler(sub_id: sub_id)
        XCTAssertTrue(pool.handlers.isEmpty)
    }
    
    func testRecordLastPong() throws {
        let pool = try setUpPool()
        let relayId = fakeRelayURL.absoluteString
        let relay = try XCTUnwrap(pool.get_relay(relayId))
        XCTAssertEqual(relay.last_pong, 0)
        
        let pongEvent = NostrConnectionEvent.ws_event(.pong(nil))
        pool.record_last_pong(relay_id: relayId, event: pongEvent)
        XCTAssertNotEqual(relay.last_pong, 0)
    }
    
    func testSeenAndCounts() throws {
        let pool = try setUpPool()
        
        XCTAssertTrue(pool.seen.isEmpty)
        XCTAssertTrue(pool.counts.isEmpty)
        
        let event = NostrEvent(id: "123", content: "", pubkey: "")
        let connectionEvent = NostrConnectionEvent.nostr_event(NostrResponse.event("", event))
        let relay_id = fakeRelayURL.absoluteString
        pool.record_seen(relay_id: relay_id, event: connectionEvent)
        
        XCTAssertTrue(pool.seen.contains("wss://some.relay.com123"))
        
        XCTAssertEqual(pool.counts[relay_id], 1)
        
        pool.record_seen(relay_id: relay_id, event: connectionEvent)
        // don't count the same event twice
        XCTAssertEqual(pool.counts[relay_id], 1)
    }
    
    func testAddQueuedRequest() throws {
        let pool = try setUpPool()
        
        XCTAssertEqual(pool.count_queued(relay: fakeRelayURL.absoluteString), 0)
        
        let req = NostrRequest.unsubscribe("")
        pool.queue_req(r: req, relay: fakeRelayURL.absoluteString)
        
        XCTAssertEqual(pool.count_queued(relay: fakeRelayURL.absoluteString), 1)
    }
    
    func testRejectTooManyQueuedRequests() throws {
        let pool = try setUpPool()
        
        let maxRequests = RelayPool.Constants.max_queued_requests
        for _ in 0..<maxRequests {
            let req = NostrRequest.unsubscribe("")
            pool.queue_req(r: req, relay: fakeRelayURL.absoluteString)
        }
        
        XCTAssertEqual(pool.count_queued(relay: fakeRelayURL.absoluteString), maxRequests)
        
        // try to add one beyond the maximum
        let req = NostrRequest.unsubscribe("")
        pool.queue_req(r: req, relay: fakeRelayURL.absoluteString)
        
        XCTAssertEqual(pool.count_queued(relay: fakeRelayURL.absoluteString), maxRequests)
    }
}
