//
//  RelayIntegrationTests.swift
//  damusTests
//
//  Integration tests for relay connections under various network conditions.
//  Uses strfry as local test relay (Docker) to test NIP-01 protocol flows.
//
//  NIP-01 Messages Tested:
//  - Client→Relay: EVENT, REQ, CLOSE
//  - Relay→Client: EVENT, OK, EOSE, CLOSED, NOTICE
//
//  Run strfry locally (with permissive config):
//    docker run -d -p 7777:7777 -v $(pwd)/test/strfry-test.conf:/etc/strfry.conf \
//      --name strfry-test ghcr.io/dockur/strfry
//
//  Run with throttling:
//    sudo throttle --profile 3g
//    xcodebuild test -only-testing:damusTests/RelayIntegrationTests
//    sudo throttle --stop
//

import XCTest
import Combine
@testable import damus

/// Integration tests that connect to a real relay (strfry) to verify
/// NIP-01 protocol handling under various network conditions.
final class RelayIntegrationTests: XCTestCase {

    // MARK: - Configuration

    /// Local strfry relay URL (Docker: docker run -p 7777:7777 dockurr/strfry)
    static let localRelayURL = RelayURL("ws://localhost:7777")!

    /// Public relay for fallback testing
    static let publicRelayURL = RelayURL("wss://relay.damus.io")!

    /// Timeout for network operations (increase for throttled tests)
    var networkTimeout: TimeInterval = 10.0

    // MARK: - Properties

    var pool: RelayPool!
    var keypair: Keypair!
    var cancellables: Set<AnyCancellable> = []
    var receivedMessages: [String] = []
    var sentMessages: [String] = []

    // MARK: - Setup/Teardown

    override func setUp() async throws {
        try await super.setUp()
        keypair = generate_new_keypair().to_keypair()
        pool = RelayPool(ndb: Ndb.test, keypair: keypair)

        receivedMessages = []
        sentMessages = []
        cancellables = []

        // Capture messages for verification
        await pool.set_message_received_function { [weak self] (message, _) in
            self?.receivedMessages.append(message)
        }
        await pool.set_message_sent_function { [weak self] (message, _) in
            self?.sentMessages.append(message)
        }
    }

    override func tearDown() async throws {
        await pool.disconnect()
        pool = nil
        keypair = nil
        cancellables.removeAll()
        try await super.tearDown()
    }

    // MARK: - Helper Methods

    /// Check if local strfry relay is running
    /// Uses environment variable FORCE_PUBLIC_RELAY=1 to skip local check
    func isLocalRelayAvailable() async -> Bool {
        // Allow forcing public relay via environment (for local dev where Docker unreachable)
        if ProcessInfo.processInfo.environment["FORCE_PUBLIC_RELAY"] == "1" {
            return false
        }

        let testPool = RelayPool(ndb: Ndb.test, keypair: keypair)
        let descriptor = RelayPool.RelayDescriptor(url: Self.localRelayURL, info: .readWrite)

        do {
            try await testPool.add_relay(descriptor)
            await testPool.connect()

            // Wait for connection with multiple checks
            for _ in 0..<5 {
                try? await Task.sleep(for: .milliseconds(500))
                if await testPool.num_connected == 1 {
                    await testPool.disconnect()
                    return true
                }
            }
            await testPool.disconnect()
            return false
        } catch {
            return false
        }
    }

    /// Get relay URL - uses local strfry if available (CI), otherwise public relay.
    /// iOS Simulator can't reach Docker localhost, but CI can.
    func getRelayURL() async -> RelayURL {
        if await isLocalRelayAvailable() {
            return Self.localRelayURL
        } else {
            // Only increase timeout if not already set higher (e.g., by throttled tests)
            if networkTimeout < 30.0 {
                networkTimeout = 30.0
            }
            return Self.publicRelayURL
        }
    }

    /// Connect to relay and wait for connection
    /// Throws if connection times out
    func connectToRelay(_ url: RelayURL) async throws {
        let descriptor = RelayPool.RelayDescriptor(url: url, info: .readWrite)
        try await pool.add_relay(descriptor)
        await pool.connect()

        // Poll for connection with async sleep
        for _ in 0..<Int(networkTimeout * 2) {
            try await Task.sleep(for: .milliseconds(500))
            let connected = await pool.num_connected
            if connected >= 1 {
                return
            }
        }
        throw NSError(domain: "RelayIntegrationTests", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: "Failed to connect to relay within \(networkTimeout) seconds"])
    }

    /// Parse JSON message to extract type (first element)
    func parseMessageType(_ message: String) -> String? {
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              let type = json.first as? String else {
            return nil
        }
        return type
    }

    /// Parse OK message: ["OK", event_id, success, message]
    func parseOKMessage(_ message: String) -> (eventId: String, success: Bool, message: String)? {
        guard let data = message.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
              json.count >= 4,
              json[0] as? String == "OK",
              let eventId = json[1] as? String,
              let success = json[2] as? Bool,
              let msg = json[3] as? String else {
            return nil
        }
        return (eventId, success, msg)
    }

    // MARK: - NIP-01 Protocol Tests

    /// Test: Connect to relay and verify connection established
    /// NIP-01: Basic WebSocket connection
    @MainActor
    func testConnectToRelay() async throws {
        let relayURL = await getRelayURL()
        try await connectToRelay(relayURL)

        let connected = await pool.num_connected
        XCTAssertEqual(connected, 1, "Should be connected to one relay")
    }

    /// Test: Send REQ and receive EOSE
    /// NIP-01: ["REQ", sub_id, filters...] → ["EOSE", sub_id]
    @MainActor
    func testSubscriptionReceivesEOSE() async throws {
        let relayURL = await getRelayURL()
        try await connectToRelay(relayURL)

        let subId = UUID().uuidString

        // Subscribe to recent metadata events (likely to have some)
        let subscribe = NostrSubscribe(filters: [
            NostrFilter(kinds: [.metadata], limit: 1)
        ], sub_id: subId)

        await pool.send(NostrRequest.subscribe(subscribe))

        // Wait for EOSE
        let eoseExpectation = XCTestExpectation(description: "Waiting for EOSE")
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            let hasEOSE = self.receivedMessages.contains { msg in
                self.parseMessageType(msg) == "EOSE"
            }
            if hasEOSE {
                eoseExpectation.fulfill()
                timer.invalidate()
            }
        }
        await fulfillment(of: [eoseExpectation], timeout: networkTimeout)

        // Verify EOSE received
        let eoseMessages = receivedMessages.filter { parseMessageType($0) == "EOSE" }
        XCTAssertFalse(eoseMessages.isEmpty, "Should receive EOSE after REQ")
    }

    /// Test: Publish event and receive OK
    /// NIP-01: ["EVENT", event] → ["OK", event_id, true/false, message]
    @MainActor
    func testPublishEventReceivesOK() async throws {
        let relayURL = await getRelayURL()
        try await connectToRelay(relayURL)

        // Create a simple text note
        let content = "Integration test note - \(UUID().uuidString)"
        guard let event = NostrEvent(
            content: content,
            keypair: keypair,
            kind: UInt32(NostrKind.text.rawValue),
            tags: []
        ) else {
            XCTFail("Failed to create event")
            return
        }

        let eventId = event.id.hex()

        // Publish event
        await pool.send(NostrRequest.event(event))

        // Wait for OK response
        let okExpectation = XCTestExpectation(description: "Waiting for OK")
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            let hasOK = self.receivedMessages.contains { msg in
                if let ok = self.parseOKMessage(msg) {
                    return ok.eventId == eventId
                }
                return false
            }
            if hasOK {
                okExpectation.fulfill()
                timer.invalidate()
            }
        }
        await fulfillment(of: [okExpectation], timeout: networkTimeout)

        // Verify OK response
        let okMessage = receivedMessages.first { msg in
            if let ok = parseOKMessage(msg) {
                return ok.eventId == eventId
            }
            return false
        }
        XCTAssertNotNil(okMessage, "Should receive OK for published event")

        if let ok = parseOKMessage(okMessage!) {
            // Note: May be false if relay rejects (e.g., rate limit, duplicate)
            // For strfry, should typically be true
            print("OK response: success=\(ok.success), message=\(ok.message)")
        }
    }

    /// Test: Close subscription with CLOSE message
    /// NIP-01: ["CLOSE", sub_id]
    @MainActor
    func testCloseSubscription() async throws {
        let relayURL = await getRelayURL()
        try await connectToRelay(relayURL)

        let subId = UUID().uuidString

        // Subscribe
        let subscribe = NostrSubscribe(filters: [
            NostrFilter(kinds: [.metadata], limit: 1)
        ], sub_id: subId)
        await pool.send(NostrRequest.subscribe(subscribe))

        // Wait for EOSE
        let eoseExpectation = XCTestExpectation(description: "Waiting for EOSE")
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            if self.receivedMessages.contains(where: { self.parseMessageType($0) == "EOSE" }) {
                eoseExpectation.fulfill()
                timer.invalidate()
            }
        }
        await fulfillment(of: [eoseExpectation], timeout: networkTimeout)

        // Close subscription
        await pool.send(NostrRequest.unsubscribe(subId))

        // Verify CLOSE was sent
        let closeSent = sentMessages.contains { msg in
            guard let data = msg.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [Any],
                  json.count >= 2,
                  json[0] as? String == "CLOSE",
                  json[1] as? String == subId else {
                return false
            }
            return true
        }
        XCTAssertTrue(closeSent, "CLOSE message should be sent")
    }

    // MARK: - Network Condition Tests

    /// Test: Connection recovery after disconnect
    /// Simulates network interruption and verifies reconnection
    @MainActor
    func testReconnectionAfterDisconnect() async throws {
        let relayURL = await getRelayURL()
        try await connectToRelay(relayURL)

        // Verify initial connection
        var connected = await pool.num_connected
        XCTAssertEqual(connected, 1)

        // Disconnect
        await pool.disconnect()

        // Wait briefly
        try? await Task.sleep(for: .seconds(1))

        connected = await pool.num_connected
        XCTAssertEqual(connected, 0, "Should be disconnected")

        // Reconnect
        await pool.connect()

        // Wait for reconnection
        let reconnectExpectation = XCTestExpectation(description: "Waiting for reconnection")
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            Task {
                if await self.pool.num_connected == 1 {
                    reconnectExpectation.fulfill()
                    timer.invalidate()
                }
            }
        }
        await fulfillment(of: [reconnectExpectation], timeout: networkTimeout)

        connected = await pool.num_connected
        XCTAssertEqual(connected, 1, "Should reconnect successfully")
    }

    /// Test: Multiple rapid subscriptions
    /// Stress test for subscription handling under load
    @MainActor
    func testMultipleRapidSubscriptions() async throws {
        let relayURL = await getRelayURL()
        try await connectToRelay(relayURL)

        let subscriptionCount = 5
        var subIds: [String] = []

        // Create multiple subscriptions rapidly
        for i in 0..<subscriptionCount {
            let subId = "stress-test-\(i)-\(UUID().uuidString)"
            subIds.append(subId)

            let subscribe = NostrSubscribe(filters: [
                NostrFilter(kinds: [.metadata], limit: 1)
            ], sub_id: subId)
            await pool.send(NostrRequest.subscribe(subscribe))
        }

        // Wait for EOSEs
        let eoseExpectation = XCTestExpectation(description: "Waiting for multiple EOSEs")
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            let eoseCount = self.receivedMessages.filter {
                self.parseMessageType($0) == "EOSE"
            }.count
            if eoseCount >= subscriptionCount {
                eoseExpectation.fulfill()
                timer.invalidate()
            }
        }
        await fulfillment(of: [eoseExpectation], timeout: networkTimeout * 2)

        // Close all subscriptions
        for subId in subIds {
            await pool.send(NostrRequest.unsubscribe(subId))
        }

        let eoseCount = receivedMessages.filter { parseMessageType($0) == "EOSE" }.count
        XCTAssertGreaterThanOrEqual(eoseCount, subscriptionCount,
            "Should receive EOSE for all subscriptions")
    }

    // MARK: - Throttled Network Tests
    // These tests are designed to run with network throttling enabled:
    //   sudo throttle --profile 3g
    //
    // They use longer timeouts and verify behavior under degraded conditions.

    /// Test: Subscription completes under 3G-like conditions
    /// Run with: sudo throttle --profile 3g
    @MainActor
    func testSubscriptionUnder3GConditions() async throws {
        // Increase timeout for throttled network
        networkTimeout = 60.0

        let relayURL = await getRelayURL()
        try await connectToRelay(relayURL)

        let subId = UUID().uuidString
        let subscribe = NostrSubscribe(filters: [
            NostrFilter(kinds: [.metadata], limit: 5)
        ], sub_id: subId)

        let startTime = Date()
        await pool.send(NostrRequest.subscribe(subscribe))

        // Wait for EOSE with extended timeout
        let eoseExpectation = XCTestExpectation(description: "Waiting for EOSE under 3G")
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            if self.receivedMessages.contains(where: { self.parseMessageType($0) == "EOSE" }) {
                eoseExpectation.fulfill()
                timer.invalidate()
            }
        }
        await fulfillment(of: [eoseExpectation], timeout: networkTimeout)

        let elapsed = Date().timeIntervalSince(startTime)
        print("Subscription completed in \(elapsed) seconds under current network conditions")

        // Verify completed
        let hasEOSE = receivedMessages.contains { parseMessageType($0) == "EOSE" }
        XCTAssertTrue(hasEOSE, "Should receive EOSE even under slow network")
    }

    /// Test: Event publish completes under degraded network
    /// Run with: sudo throttle --profile 3gslow
    @MainActor
    func testPublishUnderDegradedNetwork() async throws {
        // Increase timeout for throttled network
        networkTimeout = 60.0

        let relayURL = await getRelayURL()
        try await connectToRelay(relayURL)

        let content = "Throttled network test - \(UUID().uuidString)"
        guard let event = NostrEvent(
            content: content,
            keypair: keypair,
            kind: UInt32(NostrKind.text.rawValue),
            tags: []
        ) else {
            XCTFail("Failed to create event")
            return
        }

        let eventId = event.id.hex()
        let startTime = Date()

        await pool.send(NostrRequest.event(event))

        // Wait for OK with extended timeout
        let okExpectation = XCTestExpectation(description: "Waiting for OK under degraded network")
        Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { timer in
            let hasOK = self.receivedMessages.contains { msg in
                if let ok = self.parseOKMessage(msg) {
                    return ok.eventId == eventId
                }
                return false
            }
            if hasOK {
                okExpectation.fulfill()
                timer.invalidate()
            }
        }
        await fulfillment(of: [okExpectation], timeout: networkTimeout)

        let elapsed = Date().timeIntervalSince(startTime)
        print("Publish completed in \(elapsed) seconds under current network conditions")

        let hasOK = receivedMessages.contains { msg in
            parseOKMessage(msg)?.eventId == eventId
        }
        XCTAssertTrue(hasOK, "Should receive OK even under slow network")
    }
}

// MARK: - Throttled Test Helpers

extension RelayIntegrationTests {

    /// Check if network throttling is currently active
    /// This is a heuristic based on connection time
    func isNetworkThrottled() async -> Bool {
        let startTime = Date()

        // Try a quick connection
        let testPool = RelayPool(ndb: Ndb.test, keypair: keypair)
        let descriptor = RelayPool.RelayDescriptor(
            url: Self.publicRelayURL,
            info: .readWrite
        )

        do {
            try await testPool.add_relay(descriptor)
            await testPool.connect()

            // Wait for connection
            try? await Task.sleep(for: .seconds(5))
            await testPool.disconnect()
        } catch {
            // Ignore errors
        }

        let elapsed = Date().timeIntervalSince(startTime)

        // If connection took > 3 seconds, likely throttled
        return elapsed > 3.0
    }
}
