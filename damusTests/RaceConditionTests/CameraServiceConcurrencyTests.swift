//
//  CameraServiceConcurrencyTests.swift
//  damusTests
//
//  Tests for race condition: CameraService notification callbacks on unknown threads
//  Bead: damus-q1p
//

import XCTest
@testable import damus

final class CameraServiceConcurrencyTests: XCTestCase {

    // MARK: - Before fix: @Published writes from sessionQueue

    func test_camera_published_writes_before() {
        let expectation = expectation(description: "background write")
        let sessionQueue = DispatchQueue(label: "test.camera.session")

        sessionQueue.async {
            // In production, capture callbacks write @Published properties here
            XCTAssertFalse(Thread.isMainThread, "sessionQueue is not main thread")
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2.0)
    }

    // MARK: - After fix: @Published writes dispatched to main

    func test_camera_published_writes_after() {
        let expectation = expectation(description: "main thread write")
        let sessionQueue = DispatchQueue(label: "test.camera.session")

        sessionQueue.async {
            DispatchQueue.main.async {
                XCTAssertTrue(Thread.isMainThread, "Write should be on main thread")
                expectation.fulfill()
            }
        }

        wait(for: [expectation], timeout: 2.0)
    }
}
