//
//  CameraServiceConcurrencyTests.swift
//  damusTests
//
//  Tests for race condition: CameraService notification callbacks on unknown threads
//  Bead: damus-q1p
//
//  Fix being tested: DispatchQueue.main.async wrapping of @Published writes from sessionQueue callbacks.
//  CameraService requires AVFoundation hardware — cannot instantiate in tests.
//  Uses mock ObservableObject with identical dispatch pattern + Combine sink thread verification.
//
//  Fix-sensitivity: Without DispatchQueue.main.async, some sink deliveries fire on background
//  threads → captured threads include non-main → assertion fails. Also, concurrent value += 1
//  without main serialization can lose updates → final < 100.

import XCTest
import Combine
@testable import damus

final class CameraServiceConcurrencyTests: XCTestCase {

    // MARK: - Before fix: @Published writes from sessionQueue

    /// Demonstrates the bug: writing @Published from a background queue (like sessionQueue)
    /// causes Combine subscribers to fire on that background thread.
    func test_camera_published_writes_before() {
        class UnsafePublisher: ObservableObject {
            @Published var value: Int = 0
        }

        let publisher = UnsafePublisher()
        let sessionQueue = DispatchQueue(label: "test.camera.session")
        let expectation = expectation(description: "sink fires on background thread")
        var capturedOnMain: Bool?
        var cancellable: AnyCancellable?

        cancellable = publisher.$value
            .dropFirst()
            .sink { _ in
                capturedOnMain = Thread.isMainThread
                expectation.fulfill()
            }

        // Write directly from sessionQueue WITHOUT DispatchQueue.main.async (the bug pattern)
        sessionQueue.async {
            publisher.value = 1
        }

        wait(for: [expectation], timeout: 2.0)
        XCTAssertNotNil(capturedOnMain)
        XCTAssertFalse(capturedOnMain!, "Without main dispatch, @Published sink fires on background thread")
        cancellable?.cancel()
    }

    // MARK: - After fix: @Published writes dispatched to main

    /// 100 writes from background queues, each through DispatchQueue.main.async.
    /// Verifies: (1) every Combine delivery is on main thread, (2) no lost updates (final == 100).
    func test_camera_published_writes_after() {
        class SafePublisher: ObservableObject {
            @Published var value: Int = 0
        }

        let publisher = SafePublisher()
        let totalWrites = 100
        let expectation = expectation(description: "all writes delivered on main")
        expectation.expectedFulfillmentCount = totalWrites

        let lock = NSLock()
        var deliveryThreads: [Bool] = [] // true = main, false = background
        var cancellable: AnyCancellable?

        cancellable = publisher.$value
            .dropFirst()
            .sink { _ in
                let isMain = Thread.isMainThread
                lock.lock()
                deliveryThreads.append(isMain)
                lock.unlock()
                expectation.fulfill()
            }

        // Simulate CameraService pattern: background queues dispatch writes to main
        for _ in 0..<totalWrites {
            DispatchQueue.global().async {
                DispatchQueue.main.async {
                    publisher.value += 1
                }
            }
        }

        wait(for: [expectation], timeout: 10.0)

        lock.lock()
        let allOnMain = deliveryThreads.allSatisfy { $0 }
        let deliveryCount = deliveryThreads.count
        lock.unlock()

        XCTAssertTrue(allOnMain, "All @Published deliveries should be on main thread")
        XCTAssertEqual(deliveryCount, totalWrites, "Should receive exactly \(totalWrites) deliveries")
        XCTAssertEqual(publisher.value, totalWrites, "Main queue serialization prevents lost updates")
        cancellable?.cancel()
    }
}
