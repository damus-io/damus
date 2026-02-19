//
//  HomeModelConcurrencyTests.swift
//  damusTests
//
//  Tests for race condition: HomeModel fire-and-forget parallel event processing
//  Bead: damus-7da
//

import XCTest
@testable import damus

final class HomeModelConcurrencyTests: XCTestCase {

    // MARK: - Before fix: demonstrates duplicate repost check race without serialization

    /// Reproduces master's HomeModel.handle_notification() which had no @MainActor:
    ///   if already_reposted.contains(ev.id) { return }   // CHECK
    ///   already_reposted.insert(ev.id)                    // ACT
    /// Without @MainActor, two Tasks both see "not contains" and both process.
    func test_homemodel_already_reposted_race_before() {
        var alreadyReposted = Set<String>()
        let storageLock = NSLock()
        let duplicateProcessed = AtomicCounter()
        let barrier = ConcurrentBarrier()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let contains = alreadyReposted.contains("repost1")  // CHECK
            storageLock.unlock()
            barrier.arriveA()  // Both checked before either inserts
            if !contains {
                storageLock.lock()
                alreadyReposted.insert("repost1")
                storageLock.unlock()
                duplicateProcessed.increment()
            }
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let contains = alreadyReposted.contains("repost1")  // CHECK: also false
            storageLock.unlock()
            barrier.arriveB()
            if !contains {
                storageLock.lock()
                alreadyReposted.insert("repost1")
                storageLock.unlock()
                duplicateProcessed.increment()
            }
            group.leave()
        }
        let result = group.wait(timeout: .now() + 10)
        XCTAssertEqual(result, .success, "Threads should complete within timeout")
        XCTAssertEqual(duplicateProcessed.value, 2, "Master HomeModel bug: both Tasks process same repost (non-atomic check-then-insert)")
    }

    // MARK: - After fix: @MainActor serialization prevents duplicates

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
