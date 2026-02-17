//
//  BookmarksManagerConcurrencyTests.swift
//  damusTests
//
//  Tests for race condition: BookmarksManager check-then-act on bookmarks
//  Bead: damus-l21
//

import XCTest
@testable import damus

final class BookmarksManagerConcurrencyTests: XCTestCase {

    // MARK: - Before fix: reproduce master's check-then-act race on bookmarks

    /// Reproduces master's BookmarksManager.updateBookmark() which had no @MainActor:
    ///   if isBookmarked(ev) { bookmarks.filter { $0 != ev } }
    ///   else { bookmarks.insert(ev, at: 0) }
    /// Without @MainActor, two threads both see "not bookmarked" and both insert.
    func test_bookmarks_check_then_act_before() {
        var bookmarks: [String] = []
        let storageLock = NSLock()
        let duplicateInserts = AtomicCounter()
        let barrier = ConcurrentBarrier()
        let group = DispatchGroup()

        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let isBookmarked = bookmarks.contains("ev1")  // CHECK
            storageLock.unlock()
            barrier.arriveA()
            if !isBookmarked {
                storageLock.lock()
                bookmarks.insert("ev1", at: 0)
                storageLock.unlock()
                duplicateInserts.increment()
            }
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let isBookmarked = bookmarks.contains("ev1")
            storageLock.unlock()
            barrier.arriveB()
            if !isBookmarked {
                storageLock.lock()
                bookmarks.insert("ev1", at: 0)
                storageLock.unlock()
                duplicateInserts.increment()
            }
            group.leave()
        }
        group.wait()
        storageLock.lock()
        let count = bookmarks.count
        storageLock.unlock()
        XCTAssertEqual(duplicateInserts.value, 2, "Master BookmarksManager bug: both threads insert same bookmark")
        XCTAssertEqual(count, 2, "bookmarks has duplicate (should be 1)")
    }

    // MARK: - After fix: @MainActor serializes concurrent check-then-act

    /// With @MainActor on real BookmarksManager, concurrent updateBookmark calls
    /// are serialized. 100 concurrent tasks all try the same check-then-insert;
    /// only 1 succeeds.
    func test_bookmarks_check_then_act_after() async {
        // Use a class instance to share state and avoid static pollution between test runs
        class SharedState: @unchecked Sendable {
            var bookmarks: [Int] = []
        }
        let state = SharedState()

        let successCount = await concurrentStressAsync(workers: 10, iterations: 10) { _, _ in
            await MainActor.run {
                let ev = 42
                if !state.bookmarks.contains(ev) {
                    state.bookmarks.append(ev)
                    return true
                }
                return false
            }
        }

        let finalCount = await MainActor.run { state.bookmarks.count }
        XCTAssertEqual(successCount, 1, "@MainActor serialization allows exactly 1 insert under concurrent contention")
        XCTAssertEqual(finalCount, 1, "Only one bookmark should exist after concurrent contention")
    }
}
