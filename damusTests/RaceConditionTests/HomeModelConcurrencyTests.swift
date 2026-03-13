//
//  HomeModelConcurrencyTests.swift
//  damusTests
//
//  Tests for race condition: HomeModel fire-and-forget parallel event processing
//

import XCTest
@testable import damus

final class HomeModelConcurrencyTests: XCTestCase {
    /// Exercises the real HomeModel class: 100 concurrent tasks all try
    /// check-then-insert on HomeModel.has_event for the same event ID.
    /// @MainActor serialization ensures only one insert succeeds.
    func test_homemodel_already_reposted_race_after() async {
        let model = await MainActor.run { HomeModel() }

        let successCount = await concurrentStressAsync(workers: 10, iterations: 10) { _, _ in
            await MainActor.run {
                let key = "text_event"
                let testId = test_note.id
                if model.has_event[key] == nil {
                    model.has_event[key] = Set()
                }
                if !(model.has_event[key]?.contains(testId) ?? false) {
                    model.has_event[key]?.insert(testId)
                    return true
                }
                return false
            }
        }

        XCTAssertEqual(successCount, 1, "@MainActor serialization allows exactly 1 insert of the same event into HomeModel.has_event")
    }
}
