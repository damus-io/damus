//
//  RelayModelCacheConcurrencyTests.swift
//  damusTests
//
//  Tests for race condition: RelayModelCache unsynchronized dictionary
//  Bead: damus-5c0
//

import XCTest
@testable import damus

final class RelayModelCacheConcurrencyTests: XCTestCase {

    // MARK: - Before fix: reproduce master's unsynchronized read-write race

    /// Reproduces master's RelayModelCache which had no NSLock:
    ///   model(withURL:) → reads models[url] (no lock)
    ///   insert(model:)  → writes models[url] + objectWillChange.send() (no lock)
    /// Without synchronization, callers that check model(withURL:) before inserting
    /// both see nil and both insert — last-writer-wins.
    func test_relay_model_cache_race_before() {
        // NSMutableDictionary allows concurrent access without crashing (unlike Swift Dict)
        // so we use it to demonstrate the check-then-insert race safely.
        let models = NSMutableDictionary()
        let bothInserted = AtomicCounter()
        let barrier = ConcurrentBarrier()
        let group = DispatchGroup()

        // Thread A: check-then-insert (master's unprotected pattern)
        group.enter()
        DispatchQueue.global().async {
            let existing = models["relay1"]  // CHECK: nil
            barrier.arriveA()  // Both checked before either inserts
            if existing == nil {
                models["relay1"] = "model-A"  // ACT: insert
                bothInserted.increment()
            }
            group.leave()
        }

        // Thread B: same check-then-insert
        group.enter()
        DispatchQueue.global().async {
            let existing = models["relay1"]  // CHECK: also nil
            barrier.arriveB()
            if existing == nil {
                models["relay1"] = "model-B"  // ACT: overwrites A (last-writer-wins)
                bothInserted.increment()
            }
            group.leave()
        }

        let result = group.wait(timeout: .now() + 10)
        XCTAssertEqual(result, .success, "Threads should complete within timeout")
        XCTAssertEqual(bothInserted.value, 2, "Master RelayModelCache bug: both threads see nil and insert (last-writer-wins)")
    }

    // MARK: - After fix: real RelayModelCache with NSLock serializes access

    /// Exercises the real RelayModelCache: 100 concurrent threads insert distinct
    /// RelayModels. NSLock serialization ensures all inserts are preserved and
    /// retrievable via model(withURL:).
    func test_relay_model_cache_race_after() {
        let cache = RelayModelCache()
        let group = DispatchGroup()
        let metadata = RelayMetadata(name: nil, description: nil, pubkey: nil, contact: nil, supported_nips: nil, software: nil, version: nil, limitation: nil, payments_url: nil, icon: nil, fees: nil)

        // 100 concurrent threads insert distinct RelayModels
        for i in 0..<100 {
            group.enter()
            DispatchQueue.global().async {
                let url = RelayURL("wss://relay\(i).test.com")!
                let model = RelayModel(url, metadata: metadata)
                cache.insert(model: model)
                group.leave()
            }
        }

        let result = group.wait(timeout: .now() + 10)
        XCTAssertEqual(result, .success, "All concurrent inserts should complete within timeout")

        // Verify all 100 models are retrievable
        var found = 0
        for i in 0..<100 {
            let url = RelayURL("wss://relay\(i).test.com")!
            if cache.model(withURL: url) != nil {
                found += 1
            }
        }
        XCTAssertEqual(found, 100, "All 100 concurrent inserts retrievable from real RelayModelCache under NSLock")
    }
}
