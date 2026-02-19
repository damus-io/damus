//
//  DamusUserDefaultsConcurrencyTests.swift
//  damusTests
//
//  Tests for race condition: DamusUserDefaults non-atomic mirror writes
//  Bead: damus-14l
//

import XCTest
@testable import damus

final class DamusUserDefaultsConcurrencyTests: XCTestCase {

    // MARK: - Before fix: main write + mirror not atomic

    /// Reproduces master's DamusUserDefaults.set() which had no NSLock:
    ///   store.set(value, forKey: key)        // write main
    ///   mirrorStore?.set(value, forKey: key)  // write mirror
    /// Without NSLock, a reader between the two writes sees main='new' but mirror='old'.
    func test_user_defaults_non_atomic_before() {
        var main: [String: String] = ["key": "old"]
        var mirror: [String: String] = ["key": "old"]
        let storageLock = NSLock()
        let inconsistent = AtomicCounter()
        let barrier = ConcurrentBarrier()
        let group = DispatchGroup()

        // Writer: writes main, then mirror (non-atomic in master)
        group.enter()
        DispatchQueue.global().async {
            storageLock.lock()
            main["key"] = "new"  // Write main
            storageLock.unlock()
            barrier.arriveA()    // Reader can see inconsistent state here
            storageLock.lock()
            mirror["key"] = "new"  // Write mirror
            storageLock.unlock()
            group.leave()
        }

        // Reader: reads between the two writes
        group.enter()
        DispatchQueue.global().async {
            barrier.arriveB()
            storageLock.lock()
            let mainVal = main["key"]
            let mirrorVal = mirror["key"]
            storageLock.unlock()
            if mainVal != mirrorVal {
                inconsistent.increment()
            }
            group.leave()
        }

        group.wait()
        XCTAssertEqual(inconsistent.value, 1, "Master DamusUserDefaults bug: reader sees main='new' but mirror='old' (non-atomic write)")
    }

    // MARK: - After fix: NSLock makes write atomic

    /// Exercises the real DamusUserDefaults: 100 concurrent set() calls from
    /// background threads. NSLock ensures main + mirror writes are atomic —
    /// after all writes complete, both stores hold the same value.
    func test_user_defaults_atomic_after() {
        let suiteName = "test.atomic.main.\(UUID().uuidString)"
        let mirrorName = "test.atomic.mirror.\(UUID().uuidString)"
        let mainStore = UserDefaults(suiteName: suiteName)!
        let mirrorStore = UserDefaults(suiteName: mirrorName)!
        defer {
            UserDefaults.standard.removePersistentDomain(forName: suiteName)
            UserDefaults.standard.removePersistentDomain(forName: mirrorName)
        }

        guard let defaults = try? DamusUserDefaults(main: .custom(mainStore), mirror: [.custom(mirrorStore)]) else {
            XCTFail("Could not create DamusUserDefaults")
            return
        }

        let key = "test_key"
        let group = DispatchGroup()

        // 100 concurrent writes from background threads
        for i in 0..<100 {
            group.enter()
            DispatchQueue.global().async {
                defaults.set("value_\(i)", forKey: key)
                group.leave()
            }
        }

        group.wait()

        // After all writes, main and mirror must hold the same value
        let mainVal = mainStore.string(forKey: key)
        let mirrorVal = mirrorStore.string(forKey: key)
        XCTAssertEqual(mainVal, mirrorVal, "NSLock ensures main and mirror are always consistent after concurrent writes")
        XCTAssertNotNil(mainVal, "Value should have been written")
    }
}
