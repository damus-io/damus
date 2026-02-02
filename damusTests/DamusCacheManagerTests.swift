//
//  DamusCacheManagerTests.swift
//  damusTests
//
//  Created by Daniel D'Aquino on 2023-10-04.
//

import Foundation
import XCTest
@testable import damus
import SwiftUI

final class DamusCacheManagerTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    /// Simple smoke test to check if clearing cache will crash the system
    @MainActor
    func testCacheManagerSmoke() throws {
        for _ in Range(0...20) {
            DamusCacheManager.shared.clear_cache(damus_state: test_damus_state)
        }
    }

    /// Tests that onPhaseChange callback is invoked for each clearing phase in order.
    @MainActor
    func testCacheManagerPhaseCallbacks() throws {
        let expectation = XCTestExpectation(description: "Cache clearing completes")
        var receivedPhases: [CacheClearingPhase] = []

        DamusCacheManager.shared.clear_cache(
            damus_state: test_damus_state,
            onPhaseChange: { phase in
                receivedPhases.append(phase)
            },
            completion: {
                expectation.fulfill()
            }
        )

        wait(for: [expectation], timeout: 10.0)

        // Verify all phases were reported in order
        XCTAssertEqual(receivedPhases.count, 4, "Expected 4 phase callbacks")
        XCTAssertEqual(receivedPhases[0], .kingfisher)
        XCTAssertEqual(receivedPhases[1], .appGroup)
        XCTAssertEqual(receivedPhases[2], .cacheFolder)
        XCTAssertEqual(receivedPhases[3], .temporary)
    }

    /// Tests that CacheClearingPhase provides localized descriptions.
    func testCacheClearingPhaseDescriptions() {
        XCTAssertFalse(CacheClearingPhase.kingfisher.localizedDescription.isEmpty)
        XCTAssertFalse(CacheClearingPhase.appGroup.localizedDescription.isEmpty)
        XCTAssertFalse(CacheClearingPhase.cacheFolder.localizedDescription.isEmpty)
        XCTAssertFalse(CacheClearingPhase.temporary.localizedDescription.isEmpty)
    }
}
