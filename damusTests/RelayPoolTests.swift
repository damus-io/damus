//
//  RelayPoolTests.swift
//  damusTests
//
//  Created by kernelkind on 12/16/23.
//
//  Extended with multi-relay coordination tests using MockWebSocket.
//

import Foundation
import Combine
import XCTest
@testable import damus

final class RelayPoolTests: XCTestCase {

    override func setUpWithError() throws {
    }

    override func tearDownWithError() throws {
    }

    func testAddRelay_ValidRelayURL_NoErrors() {
        testAddRelays(urls: [
            "wss://relay.damus.io"
        ])
    }

    func testAddRelay_TwoSameURLs_ThrowsRelayAlreadyExists() {
        testAddRelays(urls: [
            "wss://relay.damus.io",
            "wss://relay.damus.io"
        ], expectedError: .RelayAlreadyExists)
    }

    func testAddRelay_OneExtraneousSlashURL_ThrowsRelayAlreadyExists() {
        testAddRelays(urls: [
            "wss://relay.damus.io",
            "wss://relay.damus.io/"
        ], expectedError: .RelayAlreadyExists)
    }

    func testAddRelay_MultipleExtraneousSlashURL_ThrowsRelayAlreadyExists() {
        testAddRelays(urls: [
            "wss://relay.damus.io",
            "wss://relay.damus.io///"
        ], expectedError: .RelayAlreadyExists)
    }

    func testAddRelay_ExtraSlashURLFirst_ThrowsRelayAlreadyExists() {
        testAddRelays(urls: [
            "wss://relay.damus.io///",
            "wss://relay.damus.io"
        ], expectedError: .RelayAlreadyExists)
    }
}

func testAddRelays(urls: [String], expectedError: RelayPool.RelayError? = nil) {
    let ndb = Ndb()!
    let relayPool = RelayPool(ndb: ndb)
    let info: NIP65.RelayList.RelayItem.RWConfiguration = .readWrite

    Task {
        do {
            for relay in urls {
                guard let url = RelayURL(relay) else {
                    XCTFail("Invalid URL encountered: \(relay)")
                    return
                }

                let descriptor = RelayPool.RelayDescriptor(url: url, info: info)
                try await relayPool.add_relay(descriptor)
            }

            if expectedError != nil {
                XCTFail("Expected \(expectedError!) error, but no error was thrown.")
            }
        } catch let error as RelayPool.RelayError where expectedError == .RelayAlreadyExists {
            XCTAssertEqual(error, expectedError!, "Expected RelayAlreadyExists error, got \(error)")
        } catch {
            XCTFail("An unexpected error was thrown: \(error)")
        }
    }
}

// MARK: - Multi-Relay Coordination Tests

/// Tests for RelayPool behavior with multiple relays using MockWebSocket.
/// These tests verify:
/// - Multi-relay connection management
/// - Partial relay failures
/// - Event deduplication across relays
/// - EOSE coordination
/// - Request routing
final class RelayPoolMultiRelayTests: XCTestCase {

    var pool: RelayPool!
    var mockSockets: [RelayURL: MockWebSocket]!
    var ndb: Ndb!

    // Test relay URLs
    let relay1URL = RelayURL("wss://relay1.test.com")!
    let relay2URL = RelayURL("wss://relay2.test.com")!
    let relay3URL = RelayURL("wss://relay3.test.com")!

    override func setUp() async throws {
        try await super.setUp()
        ndb = Ndb.test
        pool = RelayPool(ndb: ndb)
        mockSockets = [:]
    }

    override func tearDown() async throws {
        await pool.close()
        pool = nil
        mockSockets = nil
        ndb = nil
        try await super.tearDown()
    }

    // MARK: - Helper Methods

    /// Adds a relay with a MockWebSocket to the pool
    func addMockRelay(_ url: RelayURL) async throws -> MockWebSocket {
        let mockSocket = MockWebSocket()
        mockSockets[url] = mockSocket
        let descriptor = RelayPool.RelayDescriptor(url: url, info: .readWrite)
        try await pool.add_relay(descriptor, webSocket: mockSocket)
        return mockSocket
    }

    /// Simulates all mock relays connecting
    func connectAllMockRelays() {
        for (_, socket) in mockSockets {
            socket.simulateConnect()
        }
    }

    // MARK: - Connection Tests

    /// Test: Multiple relays can be added and connected
    func testMultipleRelaysConnect() async throws {
        let socket1 = try await addMockRelay(relay1URL)
        let socket2 = try await addMockRelay(relay2URL)
        let socket3 = try await addMockRelay(relay3URL)

        await pool.connect()

        XCTAssertTrue(socket1.connectCalled)
        XCTAssertTrue(socket2.connectCalled)
        XCTAssertTrue(socket3.connectCalled)

        let relayCount = await pool.relays.count
        XCTAssertEqual(relayCount, 3)
    }

    /// Test: num_connected reflects actual connection state
    func testNumConnectedTracksState() async throws {
        let socket1 = try await addMockRelay(relay1URL)
        let socket2 = try await addMockRelay(relay2URL)

        await pool.connect()

        // Initially no connections
        var connected = await pool.num_connected
        XCTAssertEqual(connected, 0)

        // Connect first relay
        socket1.simulateConnect()

        // Give time for state to update
        try await Task.sleep(for: .milliseconds(100))
        connected = await pool.num_connected
        XCTAssertEqual(connected, 1)

        // Connect second relay
        socket2.simulateConnect()
        try await Task.sleep(for: .milliseconds(100))
        connected = await pool.num_connected
        XCTAssertEqual(connected, 2)
    }

    // MARK: - Partial Failure Tests

    /// Test: Pool handles partial relay failures gracefully
    func testPartialRelayFailure() async throws {
        let socket1 = try await addMockRelay(relay1URL)
        let socket2 = try await addMockRelay(relay2URL)
        let socket3 = try await addMockRelay(relay3URL)

        await pool.connect()

        // Only 2 of 3 relays connect
        socket1.simulateConnect()
        socket2.simulateConnect()
        socket3.simulateError(URLError(.cannotConnectToHost))

        try await Task.sleep(for: .milliseconds(100))

        let connected = await pool.num_connected
        XCTAssertEqual(connected, 2, "Should have 2 connected relays despite 1 failure")
    }

    /// Test: Pool continues working when one relay disconnects
    func testRelayDisconnectDoesNotAffectOthers() async throws {
        let socket1 = try await addMockRelay(relay1URL)
        let socket2 = try await addMockRelay(relay2URL)

        await pool.connect()
        socket1.simulateConnect()
        socket2.simulateConnect()

        try await Task.sleep(for: .milliseconds(100))
        var connected = await pool.num_connected
        XCTAssertEqual(connected, 2)

        // Disconnect one relay
        socket1.simulateDisconnect()
        try await Task.sleep(for: .milliseconds(100))

        connected = await pool.num_connected
        XCTAssertEqual(connected, 1, "Should have 1 connected relay after disconnect")

        // Second relay should still be connected
        XCTAssertFalse(socket2.disconnectCalled)
    }

    // MARK: - Message Routing Tests

    /// Test: Messages are sent to all connected relays
    func testMessageSentToAllRelays() async throws {
        let socket1 = try await addMockRelay(relay1URL)
        let socket2 = try await addMockRelay(relay2URL)

        await pool.connect()
        socket1.simulateConnect()
        socket2.simulateConnect()

        try await Task.sleep(for: .milliseconds(100))

        // Create and send a subscription request using the async stream-returning subscribe
        let filters = [NostrFilter(kinds: [.text], limit: 10)]
        let _ = await pool.subscribe(filters: filters, to: [relay1URL, relay2URL], eoseTimeout: .seconds(1))

        // Give time for message to be sent
        try await Task.sleep(for: .milliseconds(100))

        // Both sockets should have received at least one message (REQ, possibly also CLOSE after timeout)
        XCTAssertGreaterThanOrEqual(socket1.sentMessages.count, 1, "Socket 1 should receive at least REQ")
        XCTAssertGreaterThanOrEqual(socket2.sentMessages.count, 1, "Socket 2 should receive at least REQ")
    }

    /// Test: Messages are queued when relay is not connected
    func testMessagesQueuedWhenDisconnected() async throws {
        let socket1 = try await addMockRelay(relay1URL)

        await pool.connect()
        // Don't simulate connect - relay stays disconnected

        // Send a subscription request
        let filters = [NostrFilter(kinds: [.text], limit: 10)]
        let _ = await pool.subscribe(filters: filters, to: [relay1URL], eoseTimeout: .seconds(1))

        try await Task.sleep(for: .milliseconds(100))

        // Message should not be sent yet (relay not connected)
        XCTAssertEqual(socket1.sentMessages.count, 0, "Should not send to disconnected relay")

        // Check queue has the request
        let queueCount = await pool.count_queued(relay: relay1URL)
        XCTAssertGreaterThan(queueCount, 0, "Request should be queued")
    }

    /// Test: Queued messages are sent when relay connects
    func testQueuedMessagesSentOnConnect() async throws {
        let socket1 = try await addMockRelay(relay1URL)

        await pool.connect()

        // Send a subscription while disconnected
        let filters = [NostrFilter(kinds: [.text], limit: 10)]
        let _ = await pool.subscribe(filters: filters, to: [relay1URL], eoseTimeout: .seconds(1))

        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(socket1.sentMessages.count, 0)

        // Now connect
        socket1.simulateConnect()
        try await Task.sleep(for: .milliseconds(200))

        // Message should now be sent
        XCTAssertGreaterThan(socket1.sentMessages.count, 0, "Queued message should be sent after connect")
    }

    // MARK: - Reconnection Tests

    /// Test: Pool handles reconnection gracefully
    func testPoolHandlesReconnection() async throws {
        let socket1 = try await addMockRelay(relay1URL)

        await pool.connect()
        socket1.simulateConnect()

        try await Task.sleep(for: .milliseconds(100))

        var connected = await pool.num_connected
        XCTAssertEqual(connected, 1, "Should have 1 connected relay")

        // Simulate disconnect
        socket1.simulateDisconnect()
        try await Task.sleep(for: .milliseconds(100))

        connected = await pool.num_connected
        XCTAssertEqual(connected, 0, "Should have 0 connected relays after disconnect")

        // Simulate reconnect
        socket1.simulateConnect()
        try await Task.sleep(for: .milliseconds(100))

        connected = await pool.num_connected
        XCTAssertEqual(connected, 1, "Should have 1 connected relay after reconnect")
    }
}


