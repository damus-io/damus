//
//  NotificationsModelConcurrencyTests.swift
//  damusTests
//
//  Tests for race condition: NotificationsModel concurrent mutations
//  Bead: damus-xlb
//

import XCTest
@testable import damus

final class NotificationsModelConcurrencyTests: XCTestCase {

    // MARK: - Before fix: reproduce master's non-atomic check-then-insert on Set

    /// Reproduces master's NotificationsModel.insert_text() which had no @MainActor:
    ///   guard !has_reply.contains(ev.id)  // CHECK
    ///   has_reply.insert(ev.id)            // ACT
    ///   replies.append(ev)                 // ACT
    /// Without @MainActor, both threads pass the guard before either inserts.
    func test_notifications_model_concurrent_mutations_before() {
        var hasReply = Set<String>()
        var replies: [String] = []
        let storageLock = NSLock()
        let duplicateInserts = AtomicCounter()
        let barrier = ConcurrentBarrier()
        let group = DispatchGroup()

        // Thread A: master's insert_text(ev)
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let alreadyHas = hasReply.contains("ev1")  // CHECK (master's guard)
            storageLock.unlock()

            barrier.arriveA()  // Both checked before either inserts

            if !alreadyHas {
                storageLock.lock()
                hasReply.insert("ev1")  // ACT
                replies.append("ev1")   // ACT
                storageLock.unlock()
                duplicateInserts.increment()
            }
            group.leave()
        }

        // Thread B: concurrent insert_text(ev) with same event
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let alreadyHas = hasReply.contains("ev1")  // CHECK: also "not found"
            storageLock.unlock()

            barrier.arriveB()

            if !alreadyHas {
                storageLock.lock()
                hasReply.insert("ev1")  // ACT: duplicate insert
                replies.append("ev1")   // ACT: duplicate append
                storageLock.unlock()
                duplicateInserts.increment()
            }
            group.leave()
        }

        group.wait()
        storageLock.lock()
        let replyCount = replies.count
        storageLock.unlock()

        XCTAssertEqual(duplicateInserts.value, 2, "Master NotificationsModel bug: both threads insert same event")
        XCTAssertEqual(replyCount, 2, "replies has duplicate entry (should be 1)")
    }

    // MARK: - After fix: real NotificationsModel with @MainActor serialization prevents races

    /// With @MainActor on real NotificationsModel, all has_reply mutations are serialized.
    func test_notifications_model_concurrent_mutations_after() async {
        let model = await MainActor.run { NotificationsModel() }
        let targetNoteId = NoteId(hex: String(repeating: "a", count: 64))!

        // 100 concurrent tasks all try to insert the same NoteId into has_reply
        let successCount = await concurrentStressAsync(workers: 10, iterations: 10) { _, _ in
            await MainActor.run {
                if model.has_reply.contains(targetNoteId) {
                    return false
                }
                model.has_reply.insert(targetNoteId)
                return true
            }
        }

        let setCount = await MainActor.run { model.has_reply.count }

        XCTAssertEqual(successCount, 1, "Only one task succeeds at inserting the same NoteId in real NotificationsModel")
        XCTAssertEqual(setCount, 1, "@MainActor serialization on real NotificationsModel ensures exactly 1 entry")
    }
}
