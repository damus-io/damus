//
//  RelayConnectionTests.swift
//  damusTests
//
//  Tests for RelayConnection behavior under various network conditions.
//  Uses MockWebSocket to simulate connection events, errors, and disconnections.
//

import XCTest
import Combine
@testable import damus

final class RelayConnectionTests: XCTestCase {

    var mockSocket: MockWebSocket!
    var connection: RelayConnection!
    var receivedEvents: [NostrConnectionEvent] = []
    var receivedWSEvents: [WebSocketEvent] = []
    var cancellables: Set<AnyCancellable> = []

    // Test relay URL
    let testURL = RelayURL("wss://test.relay.example.com")!

    override func setUp() {
        super.setUp()
        mockSocket = MockWebSocket()
        receivedEvents = []
        receivedWSEvents = []
        cancellables = []

        connection = RelayConnection(
            url: testURL,
            webSocket: mockSocket,
            handleEvent: { [weak self] event in
                self?.receivedEvents.append(event)
            },
            processUnverifiedWSEvent: { [weak self] event in
                self?.receivedWSEvents.append(event)
            }
        )
    }

    override func tearDown() {
        cancellables.removeAll()
        connection = nil
        mockSocket = nil
        super.tearDown()
    }

    // MARK: - Connection State Tests

    func testInitialState() {
        XCTAssertFalse(connection.isConnected)
        XCTAssertFalse(connection.isConnecting)
        XCTAssertEqual(connection.backoff, 1.0)
    }

    func testConnectCallsSocket() {
        connection.connect()

        XCTAssertTrue(mockSocket.connectCalled)
        XCTAssertEqual(mockSocket.connectCallCount, 1)
        XCTAssertTrue(connection.isConnecting)
    }

    func testConnectSetsConnectedStateOnSuccess() {
        let expectation = expectation(description: "Connected state updated")

        connection.$isConnected
            .dropFirst()
            .sink { isConnected in
                if isConnected {
                    expectation.fulfill()
                }
            }
            .store(in: &cancellables)

        connection.connect()
        mockSocket.simulateConnect()

        waitForExpectations(timeout: 1.0)

        XCTAssertTrue(connection.isConnected)
        XCTAssertFalse(connection.isConnecting)
    }

    func testConnectResetsBackoff() {
        // First, simulate an error to increase backoff
        connection.connect()
        mockSocket.simulateError(URLError(.networkConnectionLost))

        // Wait for backoff to be applied
        let backoffExpectation = expectation(description: "Backoff increased")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            backoffExpectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        // Now connect successfully
        mockSocket.reset()
        connection.connect(force: true)

        let connectExpectation = expectation(description: "Connected")
        connection.$isConnected
            .dropFirst()
            .sink { isConnected in
                if isConnected {
                    connectExpectation.fulfill()
                }
            }
            .store(in: &cancellables)

        mockSocket.simulateConnect()
        waitForExpectations(timeout: 1.0)

        XCTAssertEqual(connection.backoff, 1.0, "Backoff should reset to 1.0 after successful connection")
    }

    func testMultipleConnectCallsAreIgnored() {
        connection.connect()
        connection.connect()
        connection.connect()

        XCTAssertEqual(mockSocket.connectCallCount, 1, "Should only call connect once when already connecting")
    }

    func testForceConnectReconnects() {
        connection.connect()
        mockSocket.simulateConnect()

        let expectation = expectation(description: "Reconnected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        mockSocket.reset()
        connection.connect(force: true)

        XCTAssertEqual(mockSocket.connectCallCount, 1, "Force connect should reconnect")
    }

    // MARK: - Disconnection Tests

    func testDisconnectUpdatesState() {
        connection.connect()
        mockSocket.simulateConnect()

        let expectation = expectation(description: "Connected then disconnected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.connection.disconnect()
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertFalse(connection.isConnected)
        XCTAssertFalse(connection.isConnecting)
        XCTAssertTrue(mockSocket.disconnectCalled)
    }

    func testUnexpectedDisconnectTriggersReconnect() {
        connection.connect()
        mockSocket.simulateConnect()

        let reconnectExpectation = expectation(description: "Reconnect triggered")

        // Wait for initial connection, then simulate unexpected disconnect
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.mockSocket.reset()
            self.mockSocket.simulateDisconnect(closeCode: .goingAway)

            // Give time for reconnect to be triggered
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                reconnectExpectation.fulfill()
            }
        }

        waitForExpectations(timeout: 2.0)

        XCTAssertTrue(mockSocket.connectCalled, "Should have attempted to reconnect")
    }

    // MARK: - Error Handling Tests

    func testErrorIncreasesBackoff() {
        connection.connect()

        let expectation = expectation(description: "Backoff increased")

        mockSocket.simulateError(URLError(.networkConnectionLost))

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertEqual(connection.backoff, 2.0, "Backoff should double after error")
    }

    func testMultipleErrorsIncreaseBackoffExponentially() {
        connection.connect()

        // Simulate multiple errors
        for i in 1...3 {
            let errorExpectation = expectation(description: "Error \(i) processed")

            mockSocket.simulateError(URLError(.networkConnectionLost))

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                errorExpectation.fulfill()
            }
            waitForExpectations(timeout: 1.0)

            // Reset for next iteration
            mockSocket.reset()

            // Force reconnect attempt
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.connection.connect(force: true)
            }

            let reconnectExpectation = expectation(description: "Reconnect \(i)")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                reconnectExpectation.fulfill()
            }
            waitForExpectations(timeout: 1.0)
        }

        // After 3 errors: 1 -> 2 -> 4 -> 8
        XCTAssertEqual(connection.backoff, 8.0, "Backoff should be 8.0 after 3 errors (1 * 2^3)")
    }

    func testSocketNotConnectedErrorIsIgnored() {
        connection.connect()
        mockSocket.simulateConnect()

        let expectation = expectation(description: "State checked")

        // POSIX error 57 = socket not connected - should be ignored
        let error = NSError(domain: NSPOSIXErrorDomain, code: 57, userInfo: nil)
        mockSocket.simulateError(error)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        // Connection state should not change, backoff should not increase
        XCTAssertTrue(connection.isConnected, "Should still be connected after ignored error")
        XCTAssertEqual(connection.backoff, 1.0, "Backoff should not increase for ignored error")
    }

    func testCancelledTaskErrorIsIgnored() {
        connection.connect()
        mockSocket.simulateConnect()

        let expectation = expectation(description: "State checked")

        // URL error -999 = cancelled - should be ignored
        let error = NSError(domain: NSURLErrorDomain, code: -999, userInfo: nil)
        mockSocket.simulateError(error)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertTrue(connection.isConnected, "Should still be connected after cancelled error")
        XCTAssertEqual(connection.backoff, 1.0, "Backoff should not increase for cancelled error")
    }

    // MARK: - Message Sending Tests

    func testSendForwardsToSocket() {
        connection.connect()
        mockSocket.simulateConnect()

        let expectation = expectation(description: "Connected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        let testMessage = "[\"REQ\",\"test-sub\",{}]"
        connection.send_raw(testMessage)

        XCTAssertEqual(mockSocket.sentMessages.count, 1)
        if case .string(let sent) = mockSocket.sentMessages.first {
            XCTAssertEqual(sent, testMessage)
        } else {
            XCTFail("Expected string message")
        }
    }

    // MARK: - Ping Tests

    func testPingSuccessUpdatesPongTime() {
        mockSocket.pingAutoSucceed = true
        connection.connect()
        mockSocket.simulateConnect()

        let expectation = expectation(description: "Ping completed")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.connection.ping()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertNotNil(connection.last_pong, "last_pong should be set after successful ping")
    }

    func testPingFailureTriggersReconnect() {
        connection.connect()
        mockSocket.simulateConnect()

        let expectation = expectation(description: "Ping failed and reconnect triggered")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Set ping to fail with timeout error
            self.mockSocket.pingAutoResponse = URLError(.timedOut)
            self.connection.ping()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertFalse(connection.isConnected, "Should disconnect after ping failure")
    }

    // MARK: - Event Callback Tests

    func testWSEventsAreForwardedToCallback() {
        connection.connect()
        mockSocket.simulateConnect()

        let expectation = expectation(description: "Events received")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            expectation.fulfill()
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertTrue(receivedWSEvents.contains { event in
            if case .connected = event { return true }
            return false
        }, "Should have received connected event")
    }

    // MARK: - Disable Tests

    func testDisablePermanentlyPreventsReconnect() {
        connection.connect()
        mockSocket.simulateConnect()

        let expectation = expectation(description: "Disabled and disconnected")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.connection.disablePermanently()
            self.mockSocket.reset()
            self.mockSocket.simulateDisconnect()

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                expectation.fulfill()
            }
        }
        waitForExpectations(timeout: 1.0)

        XCTAssertFalse(mockSocket.connectCalled, "Should not reconnect when disabled")
    }
}

// MARK: - Network Condition Simulation Tests

extension RelayConnectionTests {

    /// Tests behavior under simulated 3G-like conditions (high latency, occasional drops)
    func testBehaviorUnderSimulated3GConditions() {
        connection.connect()

        // Simulate initial connection succeeds
        mockSocket.simulateConnect()

        let scenario = expectation(description: "3G scenario complete")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Simulate intermittent disconnect (common on 3G)
            self.mockSocket.simulateDisconnect(closeCode: .goingAway, reason: "Network changed")

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                // Connection should be attempting reconnect
                XCTAssertFalse(self.connection.isConnected)

                // Simulate reconnect succeeds
                self.mockSocket.simulateConnect()

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    scenario.fulfill()
                }
            }
        }

        waitForExpectations(timeout: 2.0)

        XCTAssertTrue(connection.isConnected, "Should recover from 3G-style intermittent disconnect")
    }

    /// Tests that multiple rapid disconnects don't cause issues
    func testRapidDisconnectsHandledGracefully() {
        connection.connect()
        mockSocket.simulateConnect()

        let scenario = expectation(description: "Rapid disconnects handled")

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Rapid fire disconnects
            for i in 0..<5 {
                DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.02) {
                    self.mockSocket.simulateDisconnect()
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                scenario.fulfill()
            }
        }

        waitForExpectations(timeout: 2.0)

        // Should not crash, connection state should be consistent
        XCTAssertFalse(connection.isConnected)
    }
}
