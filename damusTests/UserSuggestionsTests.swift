//
//  UserSuggestions.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2025-05-19.
//

import XCTest
@testable import damus

final class UserSuggestions: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        do {
            let _ = try SuggestedUsersViewModel.loadUserSuggestions()
        }
        catch {
            XCTFail(error.localizedDescription)
        }
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
