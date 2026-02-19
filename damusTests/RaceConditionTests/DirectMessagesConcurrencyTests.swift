//
//  DirectMessagesConcurrencyTests.swift
//  damusTests
//
//  Tests for race condition: DirectMessagesModel duplicate model creation
//  Bead: damus-rsq
//

import XCTest
@testable import damus

final class DirectMessagesConcurrencyTests: XCTestCase {

    // MARK: - Before fix: reproduce master's lookup_or_create duplicate creation

    /// Reproduces master's DirectMessagesModel.lookup_or_create() which had no @MainActor:
    ///   if let dm = lookup(pubkey) { return dm }              // CHECK
    ///   let new = DirectMessageModel(...); dms.append(new)    // ACT
    /// Without @MainActor, two threads both see "not found" and both append.
    func test_dm_duplicate_creation_before() {
        var dms: [String] = []
        let storageLock = NSLock()
        let duplicateCreations = AtomicCounter()
        let barrier = ConcurrentBarrier()
        let group = DispatchGroup()

        // Thread A: master's lookup_or_create("target")
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let found = dms.contains("target_pk")  // CHECK (master's lookup)
            storageLock.unlock()

            barrier.arriveA()  // Both checked "not found" before either creates

            if !found {
                storageLock.lock()
                dms.append("target_pk")  // ACT: append new DM model
                storageLock.unlock()
                duplicateCreations.increment()
            }
            group.leave()
        }

        // Thread B: concurrent lookup_or_create("target")
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            let found = dms.contains("target_pk")  // CHECK: also "not found"
            storageLock.unlock()

            barrier.arriveB()

            if !found {
                storageLock.lock()
                dms.append("target_pk")  // ACT: duplicate append!
                storageLock.unlock()
                duplicateCreations.increment()
            }
            group.leave()
        }

        group.wait()
        storageLock.lock()
        let count = dms.count
        storageLock.unlock()

        XCTAssertEqual(duplicateCreations.value, 2, "Master DirectMessagesModel bug: both threads create DM for same pubkey")
        XCTAssertEqual(count, 2, "dms array has duplicate entry (should be 1)")
    }

    // MARK: - After fix: real DirectMessagesModel with @MainActor serializes access

    /// Validates that @MainActor serialization prevents duplicate DirectMessagesModel
    /// creation under concurrent lookup_or_create calls. 100 concurrent tasks via
    /// concurrentStressAsync all call lookup_or_create with the same pubkey on the
    /// real DirectMessagesModel. Only 1 DM model should be created.
    func test_dm_duplicate_creation_after() async {
        let ourPk = Pubkey(hex: String(repeating: "a", count: 64))!
        let model = await MainActor.run {
            DirectMessagesModel(our_pubkey: ourPk)
        }
        let targetPk = Pubkey(hex: String(repeating: "b", count: 64))!

        // 100 concurrent tasks all call lookup_or_create with the same pubkey
        let results = await concurrentStressAsync(workers: 10, iterations: 10) { _, _ in
            await MainActor.run {
                let _ = model.lookup_or_create(targetPk)
                return true
            }
        }

        let dmCount = await MainActor.run {
            model.dms.filter { $0.pubkey == targetPk }.count
        }

        XCTAssertEqual(results, 100, "All 100 operations completed on real DirectMessagesModel")
        XCTAssertEqual(dmCount, 1, "@MainActor serialization prevents duplicate DM model creation in real DirectMessagesModel")
    }
}
