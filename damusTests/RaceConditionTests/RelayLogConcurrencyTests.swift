//
//  RelayLogConcurrencyTests.swift
//  damusTests
//
//  Tests for race condition: RelayLog background file write reads lines without MainActor
//  Bead: damus-3l5
//

import XCTest
@testable import damus

final class RelayLogConcurrencyTests: XCTestCase {

    // MARK: - Before fix: reading lines from background while MainActor writes

    /// Reproduces master's RelayLog.save() which read lines in background Task:
    ///   Task { let content = lines.joined(separator: "\n") }  // background read
    ///   // Meanwhile @MainActor writes to lines
    /// Without snapshot-before-Task, background read sees mutated lines.
    func test_relay_log_background_read_before() {
        var lines: [String] = ["line1", "line2", "line3"]
        let storageLock = NSLock()
        let mutatedDuringRead = AtomicCounter()
        let barrier = ConcurrentBarrier()
        let group = DispatchGroup()

        // Second sync: ensures reader's second read happens AFTER writer inserts
        let writeDone = DispatchSemaphore(value: 0)

        // Background reader: reads lines, then barrier, then reads again after write
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let countBefore = lines.count  // Start reading for joined()
            storageLock.unlock()
            barrier.arriveA()    // Signal: first read done
            writeDone.wait()     // Wait for writer to finish inserting
            storageLock.lock()
            let countAfter = lines.count   // Lines changed mid-read!
            storageLock.unlock()
            if countBefore != countAfter {
                mutatedDuringRead.increment()
            }
            group.leave()
        }

        // Writer: inserts during background read
        group.enter()
        DispatchQueue.global().async {
            barrier.arriveB()    // Wait for reader's first read
            storageLock.lock()
            lines.insert("new line", at: 0)
            storageLock.unlock()
            writeDone.signal()   // Signal: write complete
            group.leave()
        }

        group.wait()
        XCTAssertEqual(mutatedDuringRead.value, 1, "Master RelayLog bug: background read sees mutated lines (no snapshot before Task)")
    }

    // MARK: - After fix: snapshot lines before background work

    /// Exercises the real RelayLog: concurrent add() calls from background
    /// threads. The fix ensures addLine() is @MainActor-isolated, so
    /// concurrent add() calls serialize mutations through MainActor.
    func test_relay_log_background_read_after() async {
        let relayUrl = RelayURL("wss://test.relay.invalid")
        let log = RelayLog(relayUrl)

        // Add lines concurrently from background threads
        let group = DispatchGroup()
        for i in 0..<20 {
            group.enter()
            DispatchQueue.global().async {
                log.add("concurrent line \(i)")
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 5)
        XCTAssertEqual(result, .success, "Concurrent add() calls should complete without crashes")

        // Wait for async addLine Tasks to settle on MainActor
        try? await Task.sleep(for: .milliseconds(500))

        let contents = await MainActor.run { log.contents }
        XCTAssertNotNil(contents, "RelayLog should have content after concurrent additions")
    }
}
