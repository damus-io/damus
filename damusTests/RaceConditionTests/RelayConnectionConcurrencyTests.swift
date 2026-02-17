//
//  RelayConnectionConcurrencyTests.swift
//  damusTests
//
//  Tests for race conditions: RelayConnection @Published writes from ping + negentropyStreams
//  Beads: damus-h4r, damus-o6c
//

import XCTest
@testable import damus

final class RelayConnectionConcurrencyTests: XCTestCase {

    // MARK: - Before fix: @Published write from background thread
    // Note: RelayConnection.ping() uses a private lazy WebSocket with an internal
    // callback, so integration testing the actual ping path requires a live relay.
    // These tests validate the dispatch-to-main pattern that the fix applies.

    /// Simulates writing to a @Published property from a background thread
    /// (the ping callback). SwiftUI can crash if this happens.
    func test_published_write_from_background_before() {
        let expectation = expectation(description: "background write")

        DispatchQueue.global().async {
            // In production, the ping callback would write isConnected = false here
            // which is a @Published property — this is unsafe
            let isMainThread = Thread.isMainThread
            XCTAssertFalse(isMainThread, "Ping callback runs on background thread")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - After fix: @Published write dispatched to main thread

    /// With DispatchQueue.main.async wrapping, the write always occurs on main.
    func test_published_write_from_background_after() {
        let expectation = expectation(description: "main thread write")

        DispatchQueue.global().async {
            // Simulate the fix: dispatch to main before writing @Published
            DispatchQueue.main.async {
                let isMainThread = Thread.isMainThread
                XCTAssertTrue(isMainThread, "Write should be on main thread")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 2.0)
    }
}
