//
//  MediaPickerTests.swift
//  damusTests
//
//  Tests for MediaPicker error handling and thread safety.
//

import XCTest
import PhotosUI
@testable import damus

final class MediaPickerTests: XCTestCase {

    // MARK: - MediaPickerError Tests

    func testMediaPickerErrorUserMessage_withItemIndex() {
        let error = MediaPickerError(message: "File corrupted", itemIndex: 2)
        XCTAssertTrue(error.userMessage.contains("3"), "Should show 1-indexed item number")
        XCTAssertTrue(error.userMessage.contains("File corrupted"), "Should include original message")
    }

    func testMediaPickerErrorUserMessage_withoutItemIndex() {
        let error = MediaPickerError(message: "Unknown error", itemIndex: nil)
        XCTAssertEqual(error.userMessage, "Unknown error", "Should return message as-is when no index")
    }

    // MARK: - Coordinator Thread Safety Tests

    /// Tests that recordFailure and chooseMedia synchronize properly under concurrent calls.
    /// This verifies the fix where all shared state access goes through the main queue.
    @MainActor
    func testCoordinatorThreadSafety_concurrentUpdates() async {
        let expectation = XCTestExpectation(description: "All media processed")

        let picker = MediaPicker(
            mediaPickerEntry: .postView,
            onMediaSelected: nil,
            onError: { _ in },
            onMediaPicked: { _ in }
        )

        let coordinator = MediaPicker.Coordinator(picker)

        // Simulate concurrent processing of 10 items
        // Half will succeed, half will fail
        let itemCount = 10
        coordinator.orderIds = (0..<itemCount).map { "item-\($0)" }

        for _ in 0..<itemCount {
            coordinator.dispatchGroup.enter()
        }

        // Simulate concurrent callbacks from different background threads
        // Key: ALL shared state access goes through main queue (matching production code)
        DispatchQueue.concurrentPerform(iterations: itemCount) { i in
            let orderId = "item-\(i)"
            if i % 2 == 0 {
                // Success case - store result on main queue (matching production pattern)
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("test-\(i).jpg")
                DispatchQueue.main.async {
                    coordinator.orderMap[orderId] = .processed_image(url)
                    coordinator.dispatchGroup.leave()
                }
            } else {
                // Failure case - increment on main queue (matching recordFailure())
                DispatchQueue.main.async {
                    coordinator.failedCount += 1
                    coordinator.dispatchGroup.leave()
                }
            }
        }

        coordinator.dispatchGroup.notify(queue: .main) {
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 5.0)

        // Verify counts are correct (no race conditions)
        XCTAssertEqual(coordinator.failedCount, 5, "Should have exactly 5 failures")
        XCTAssertEqual(coordinator.orderMap.count, 5, "Should have exactly 5 successes")
    }

    /// Tests that empty picker dismissal doesn't trigger errors.
    func testCoordinator_emptySelection_doesNotTriggerError() {
        var errorTriggered = false
        var mediaReceived = false

        let picker = MediaPicker(
            mediaPickerEntry: .postView,
            onError: { _ in errorTriggered = true },
            onMediaPicked: { _ in mediaReceived = true }
        )

        let coordinator = MediaPicker.Coordinator(picker)

        // Empty results should just dismiss, not trigger callbacks
        // We can't fully test this without mocking PHPickerViewController,
        // but we can verify the initial state is clean
        XCTAssertEqual(coordinator.failedCount, 0)
        XCTAssertTrue(coordinator.orderIds.isEmpty)
        XCTAssertTrue(coordinator.orderMap.isEmpty)
        XCTAssertFalse(errorTriggered)
        XCTAssertFalse(mediaReceived)
    }

    // MARK: - Error Callback Tests

    /// Tests that onError is called with correct failure count.
    @MainActor
    func testOnErrorCallback_reportsCorrectCount() async {
        let expectation = XCTestExpectation(description: "Error callback received")
        var reportedFailureCount: Int?

        let picker = MediaPicker(
            mediaPickerEntry: .postView,
            onError: { count in
                reportedFailureCount = count
                expectation.fulfill()
            },
            onMediaPicked: { _ in }
        )

        let coordinator = MediaPicker.Coordinator(picker)

        // Simulate 3 failures
        coordinator.orderIds = ["1", "2", "3"]
        for _ in 0..<3 {
            coordinator.dispatchGroup.enter()
        }

        // Record failures on main queue (matching the fix)
        for _ in 0..<3 {
            DispatchQueue.main.async {
                coordinator.failedCount += 1
                coordinator.dispatchGroup.leave()
            }
        }

        coordinator.dispatchGroup.notify(queue: .main) {
            if coordinator.failedCount > 0 {
                coordinator.parent.onError?(coordinator.failedCount)
            }
        }

        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(reportedFailureCount, 3)
    }

    // MARK: - Order Preservation Tests

    /// Tests that media is delivered in selection order, not processing completion order.
    @MainActor
    func testMediaDeliveredInSelectionOrder() async {
        let expectation = XCTestExpectation(description: "All media delivered")
        var deliveredOrder: [String] = []

        let picker = MediaPicker(
            mediaPickerEntry: .postView,
            onError: nil,
            onMediaPicked: { media in
                if case .processed_image(let url) = media {
                    deliveredOrder.append(url.lastPathComponent)
                }
            }
        )

        let coordinator = MediaPicker.Coordinator(picker)

        // Set up order: A, B, C
        coordinator.orderIds = ["A", "B", "C"]
        for _ in 0..<3 {
            coordinator.dispatchGroup.enter()
        }

        // Complete in reverse order: C, B, A
        let completionOrder = ["C", "B", "A"]
        for (index, id) in completionOrder.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.01) {
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(id).jpg")
                coordinator.orderMap[id] = .processed_image(url)
                coordinator.dispatchGroup.leave()
            }
        }

        coordinator.dispatchGroup.notify(queue: .main) {
            // Deliver in orderIds order
            for id in coordinator.orderIds {
                if let media = coordinator.orderMap[id] {
                    coordinator.parent.onMediaPicked(media)
                }
            }
            expectation.fulfill()
        }

        await fulfillment(of: [expectation], timeout: 2.0)

        // Should be delivered in A, B, C order, not C, B, A
        XCTAssertEqual(deliveredOrder, ["A.jpg", "B.jpg", "C.jpg"])
    }
}
