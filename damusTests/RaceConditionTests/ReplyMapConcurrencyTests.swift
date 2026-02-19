//
//  ReplyMapConcurrencyTests.swift
//  damusTests
//
//  Tests for race condition: ReplyMap dictionary check-then-insert race
//  Bead: damus-2jo
//

import XCTest
@testable import damus

final class ReplyMapConcurrencyTests: XCTestCase {

    // MARK: - Before fix: reproduce master's check-then-insert race

    /// Reproduces the exact logic from master's ReplyMap.add(id:reply_id:):
    ///   ensure_set: if replies[id] == nil { replies[id] = Set() }
    ///   if replies[id]!.contains(reply_id) { return false }
    ///   replies[id]!.insert(reply_id)
    /// Without NSLock, the nil-check and set-creation are not atomic.
    /// We use lock-protected storage to avoid Swift UB crashes, but place the
    /// ConcurrentBarrier between CHECK and ACT to reproduce the exact race window.
    func test_reply_map_race_before() {
        var replies: [String: Set<String>] = [:]
        let storageLock = NSLock()
        let setsCreated = AtomicCounter()
        let barrier = ConcurrentBarrier()
        let group = DispatchGroup()

        // Thread A: master's ensure_set + add
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let needsCreate = replies["note"] == nil  // CHECK
            storageLock.unlock()

            barrier.arriveA()  // Both threads checked before either acts

            if needsCreate {
                storageLock.lock()
                replies["note"] = Set()  // ACT: creates set (may overwrite B's)
                storageLock.unlock()
                setsCreated.increment()
            }
            storageLock.lock()
            replies["note"]?.insert("reply-A")
            storageLock.unlock()
            group.leave()
        }

        // Thread B: same pattern
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let needsCreate = replies["note"] == nil  // CHECK
            storageLock.unlock()

            barrier.arriveB()

            if needsCreate {
                storageLock.lock()
                replies["note"] = Set()  // ACT: second Set() overwrites first
                storageLock.unlock()
                setsCreated.increment()
            }
            storageLock.lock()
            replies["note"]?.insert("reply-B")
            storageLock.unlock()
            group.leave()
        }

        let result1 = group.wait(timeout: .now() + 10)
        XCTAssertEqual(result1, .success, "Threads should complete within timeout")
        // PROOF: Both threads saw nil and created a Set — the second overwrites the first.
        // On master, this loses replies inserted before the overwrite.
        XCTAssertEqual(setsCreated.value, 2, "Master ReplyMap bug: both threads create Set() due to non-atomic check-then-insert")
    }

    // MARK: - After fix: real ReplyMap with NSLock serializes concurrent adds

    /// Exercises the real ReplyMap: 10 threads × 100 inserts = 1000 unique reply IDs
    /// for the same note. NSLock serialization ensures all inserts are preserved
    /// and retrievable via lookup().
    func test_reply_map_race_after() {
        let replyMap = ReplyMap()
        let noteId = NoteId(hex: String(repeating: "a", count: 64))!
        let group = DispatchGroup()

        // 10 threads × 100 inserts = 1000 unique reply_ids
        for worker in 0..<10 {
            for i in 0..<100 {
                group.enter()
                DispatchQueue.global().async {
                    let hex = String(repeating: "0", count: 56) + String(format: "%04x%04x", worker, i)
                    let replyId = NoteId(hex: hex)!
                    replyMap.add(id: noteId, reply_id: replyId)
                    group.leave()
                }
            }
        }

        let result2 = group.wait(timeout: .now() + 10)
        XCTAssertEqual(result2, .success, "All concurrent inserts should complete within timeout")
        let replies = replyMap.lookup(noteId)
        XCTAssertEqual(replies?.count, 1000, "All 1000 concurrent inserts preserved in real ReplyMap under NSLock")
    }
}
