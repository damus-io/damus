//
//  MockWebSocket.swift
//  damusTests
//
//  Created for testing WebSocket/relay behavior under simulated network conditions.
//

import Combine
import Foundation
@testable import damus

/// A mock WebSocket implementation for testing RelayConnection behavior.
///
/// This mock allows tests to simulate various WebSocket events (connect, disconnect,
/// errors, messages) without requiring real network connections. Use it to test:
/// - Reconnection logic with exponential backoff
/// - Error handling and recovery
/// - Message sending and receiving
/// - Connection state transitions
///
/// Example usage:
/// ```swift
/// let mockSocket = MockWebSocket()
/// let connection = RelayConnection(
///     url: testURL,
///     webSocket: mockSocket,
///     handleEvent: { _ in },
///     processUnverifiedWSEvent: { _ in }
/// )
///
/// connection.connect()
/// mockSocket.simulateConnect()  // Triggers .connected event
/// XCTAssertTrue(connection.isConnected)
///
/// mockSocket.simulateError(URLError(.networkConnectionLost))
/// // Connection should attempt reconnect with backoff
/// ```
class MockWebSocket: WebSocketProtocol {
    // MARK: - WebSocketProtocol Conformance

    /// Publisher for WebSocket events that RelayConnection subscribes to
    let subject = PassthroughSubject<WebSocketEvent, Never>()

    // MARK: - Test Observation Properties

    /// Whether connect() was called
    private(set) var connectCalled = false

    /// Number of times connect() was called
    private(set) var connectCallCount = 0

    /// Whether disconnect() was called
    private(set) var disconnectCalled = false

    /// Number of times disconnect() was called
    private(set) var disconnectCallCount = 0

    /// The close code from the last disconnect call
    private(set) var lastDisconnectCloseCode: URLSessionWebSocketTask.CloseCode?

    /// All messages sent through this socket
    private(set) var sentMessages: [URLSessionWebSocketTask.Message] = []

    /// Ping handlers waiting for response
    private(set) var pendingPingHandlers: [(Error?) -> Void] = []

    // MARK: - Configuration

    /// If set, ping() will automatically call the handler with this error
    var pingAutoResponse: Error? = nil

    /// If true, ping() will automatically succeed (call handler with nil)
    var pingAutoSucceed = false

    // MARK: - Thread Safety

    private let lock = NSLock()

    // MARK: - WebSocketProtocol Methods

    func connect() {
        lock.withLock {
            connectCalled = true
            connectCallCount += 1
        }
    }

    func disconnect(closeCode: URLSessionWebSocketTask.CloseCode, reason: Data?) {
        lock.withLock {
            disconnectCalled = true
            disconnectCallCount += 1
            lastDisconnectCloseCode = closeCode
        }
    }

    func send(_ message: URLSessionWebSocketTask.Message) {
        lock.withLock {
            sentMessages.append(message)
        }
    }

    func ping(receiveHandler: @escaping (Error?) -> Void) {
        lock.withLock {
            if pingAutoSucceed {
                receiveHandler(nil)
            } else if let error = pingAutoResponse {
                receiveHandler(error)
            } else {
                pendingPingHandlers.append(receiveHandler)
            }
        }
    }

    // MARK: - Test Simulation Methods

    /// Simulates a successful WebSocket connection
    func simulateConnect() {
        subject.send(.connected)
    }

    /// Simulates a WebSocket disconnection
    /// - Parameters:
    ///   - closeCode: The close code (default: .goingAway)
    ///   - reason: Optional reason string
    func simulateDisconnect(closeCode: URLSessionWebSocketTask.CloseCode = .goingAway, reason: String? = nil) {
        subject.send(.disconnected(closeCode, reason))
    }

    /// Simulates a WebSocket error
    /// - Parameter error: The error to send
    func simulateError(_ error: Error) {
        subject.send(.error(error))
    }

    /// Simulates a network connection lost error
    func simulateNetworkLost() {
        simulateError(URLError(.networkConnectionLost))
    }

    /// Simulates a timeout error
    func simulateTimeout() {
        simulateError(URLError(.timedOut))
    }

    /// Simulates receiving a text message
    /// - Parameter text: The message text
    func simulateMessage(_ text: String) {
        subject.send(.message(.string(text)))
    }

    /// Simulates receiving a Nostr event message
    /// - Parameters:
    ///   - subscriptionId: The subscription ID
    ///   - event: JSON string of the event
    func simulateNostrEvent(subscriptionId: String, event: String) {
        let message = "[\"EVENT\",\"\(subscriptionId)\",\(event)]"
        simulateMessage(message)
    }

    /// Simulates receiving an EOSE (End of Stored Events) message
    /// - Parameter subscriptionId: The subscription ID
    func simulateEOSE(subscriptionId: String) {
        simulateMessage("[\"EOSE\",\"\(subscriptionId)\"]")
    }

    /// Simulates receiving an OK message (event accepted/rejected)
    /// - Parameters:
    ///   - eventId: The event ID
    ///   - accepted: Whether the event was accepted
    ///   - message: Optional message
    func simulateOK(eventId: String, accepted: Bool, message: String = "") {
        simulateMessage("[\"OK\",\"\(eventId)\",\(accepted),\"\(message)\"]")
    }

    /// Simulates receiving a NOTICE message
    /// - Parameter message: The notice message
    func simulateNotice(_ message: String) {
        simulateMessage("[\"NOTICE\",\"\(message)\"]")
    }

    /// Responds to the oldest pending ping
    /// - Parameter error: Error to return (nil for success)
    func respondToPing(error: Error? = nil) {
        lock.withLock {
            guard !pendingPingHandlers.isEmpty else { return }
            let handler = pendingPingHandlers.removeFirst()
            handler(error)
        }
    }

    // MARK: - Test Reset

    /// Resets all state for a fresh test
    func reset() {
        lock.withLock {
            connectCalled = false
            connectCallCount = 0
            disconnectCalled = false
            disconnectCallCount = 0
            lastDisconnectCloseCode = nil
            sentMessages.removeAll()
            pendingPingHandlers.removeAll()
            pingAutoResponse = nil
            pingAutoSucceed = false
        }
    }
}
