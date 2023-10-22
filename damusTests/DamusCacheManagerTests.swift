//
//  DamusCacheManagerTests.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2023-10-04.
//

import Foundation

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
    func testCacheManagerSmoke() throws {
        for _ in Range(0...20) {
            DamusCacheManager.shared.clear_cache(damus_state: test_damus_state)
        }
    }
}
