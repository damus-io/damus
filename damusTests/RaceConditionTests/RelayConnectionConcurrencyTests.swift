//
//  RelayConnectionConcurrencyTests.swift
//  damusTests
//
//  Tests for race conditions: RelayConnection @Published writes from ping + negentropyStreams
//  Beads: damus-h4r, damus-o6c
//
//  Fix being tested: DispatchQueue.main.async wrapping of @Published writes in receive(event:)
//  Fix-sensitivity: Removing DispatchQueue.main.async from receive(event: .connected) causes
//  self.isConnected = true to fire on processEventsTask thread → Combine sink captures
//  non-main thread → _after assertion fails deterministically.

import XCTest
import Combine
@testable import damus

final class RelayConnectionConcurrencyTests: XCTestCase {

    // MARK: - Before fix: @Published write from background thread bypasses main

    /// Demonstrates the bug pattern: writing @Published from a background thread
    /// causes Combine subscribers to receive values on that background thread.
    /// SwiftUI would crash if observing this property.
    func test_published_write_from_background_before() {
        // Mock ObservableObject with @Published — same pattern as RelayConnection.isConnected
        class UnsafePublisher: ObservableObject {
            @Published var isConnected = false
        }

        let publisher = UnsafePublisher()
        let expectation = expectation(description: "sink fires on background thread")
        var capturedOnMain: Bool?
        var cancellable: AnyCancellable?

        // Subscribe on main thread — Combine delivers on the thread that mutates
        cancellable = publisher.$isConnected
            .dropFirst() // skip initial value
            .sink { _ in
                capturedOnMain = Thread.isMainThread
                expectation.fulfill()
            }

        // Write from background WITHOUT DispatchQueue.main.async (the bug pattern)
        DispatchQueue.global().async {
            publisher.isConnected = true
        }

        wait(for: [expectation], timeout: 2.0)
        XCTAssertNotNil(capturedOnMain)
        XCTAssertFalse(capturedOnMain!, "Without main dispatch, @Published sink fires on background thread")
        cancellable?.cancel()
    }

    // MARK: - After fix: @Published write dispatched to main thread via wsEventQueue

    /// Uses real RelayConnection: injects a .connected event into wsEventQueue,
    /// which flows through processEventsTask → receive(event:) → DispatchQueue.main.async { isConnected = true }.
    /// Combine sink verifies the write lands on the main thread.
    func test_published_write_from_background_after() {
        guard let url = RelayURL("wss://relay.test.invalid") else {
            XCTFail("Could not create RelayURL")
            return
        }

        let connection = RelayConnection(
            url: url,
            handleEvent: { _ in },
            processUnverifiedWSEvent: { _ in }
        )

        let expectation = expectation(description: "isConnected sink fires on main thread")
        var capturedOnMain: Bool?
        var cancellable: AnyCancellable?

        cancellable = connection.$isConnected
            .dropFirst() // skip initial false
            .sink { _ in
                capturedOnMain = Thread.isMainThread
                expectation.fulfill()
            }

        // Inject .connected event into the queue — processEventsTask will pick it up
        // and call receive(event:) which dispatches @Published writes to main
        Task {
            await connection.wsEventQueue.add(item: .connected)
        }

        wait(for: [expectation], timeout: 5.0)
        XCTAssertNotNil(capturedOnMain)
        XCTAssertTrue(capturedOnMain!, "With DispatchQueue.main.async fix, @Published sink fires on main thread")

        // Cleanup: cancel the processing task to avoid dangling Task
        connection.wsEventProcessTask?.cancel()
        cancellable?.cancel()
    }
}
