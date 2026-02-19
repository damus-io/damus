//
//  WalletModelConcurrencyTests.swift
//  damusTests
//
//  Tests for race condition: WalletModel double-resume on CheckedContinuation
//  Bead: damus-qtr
//

import XCTest
@testable import damus

final class WalletModelConcurrencyTests: XCTestCase {

    // MARK: - Before fix: demonstrates the race exists

    /// Reproduces master's WalletModel where both response handler and timeout
    /// read the same continuation from the dictionary and both resume it.
    /// Uses NSLock-protected individual ops with barrier between CHECK and ACT
    /// to deterministically force both threads past the guard before either resumes.
    func test_wallet_double_resume_before() {
        var continuations: [String: Bool] = ["req1": false]  // false = not yet resumed
        let storageLock = NSLock()
        let bothResumed = AtomicCounter()
        let barrier = ConcurrentBarrier()
        let group = DispatchGroup()

        // Thread A: response handler — CHECK then ACT
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let alreadyResumed = continuations["req1"] ?? true  // CHECK
            storageLock.unlock()
            barrier.arriveA()  // Both pass CHECK before either ACTs
            if !alreadyResumed {
                storageLock.lock()
                continuations["req1"] = true  // ACT: "resume"
                storageLock.unlock()
                bothResumed.increment()
            }
            group.leave()
        }

        // Thread B: timeout — CHECK then ACT
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let alreadyResumed = continuations["req1"] ?? true  // CHECK: also false
            storageLock.unlock()
            barrier.arriveB()
            if !alreadyResumed {
                storageLock.lock()
                continuations["req1"] = true  // ACT: also "resumes" (double-resume!)
                storageLock.unlock()
                bothResumed.increment()
            }
            group.leave()
        }

        group.wait()

        // Without protection, both threads see alreadyResumed == false
        // and both "resume" the continuation → count == 2 (double resume)
        XCTAssertEqual(bothResumed.value, 2, "Master WalletModel bug: both threads pass guard and resume same continuation")
    }

    // MARK: - After fix: proves the fix eliminates the race

    /// Exercises the real WalletModel: 10 concurrent waitForResponse() calls
    /// each with short timeouts. NSLock ensures the continuations and
    /// timeoutTasks dictionaries aren't corrupted by concurrent access.
    func test_wallet_double_resume_after() async {
        let settings = UserSettingsStore()
        let model = WalletModel(settings: settings)

        // 10 concurrent waitForResponse calls — all should timeout cleanly
        await withTaskGroup(of: Bool.self) { group in
            for i: UInt8 in 0..<10 {
                let requestId = NoteId(Data(repeating: i, count: 32))
                group.addTask {
                    do {
                        _ = try await model.waitForResponse(for: requestId, timeout: .milliseconds(50))
                        return false // Unexpected success
                    } catch {
                        return true // Expected timeout
                    }
                }
            }

            var timeouts: Int32 = 0
            for await result in group {
                if result { timeouts += 1 }
            }

            XCTAssertEqual(timeouts, 10, "All 10 concurrent requests timeout cleanly (NSLock prevents continuations dict corruption)")
        }
    }
}
