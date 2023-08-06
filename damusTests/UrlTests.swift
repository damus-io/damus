//
//  UrlTests.swift
//  damusTests
//
//  Created by William Casarin on 2023-08-06.
//

import XCTest
@testable import damus

final class UrlTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testRelayUrlStripsEndingSlash() throws {
        let url1 = RelayURL("wss://jb55.com/")!
        let url2 = RelayURL("wss://jb55.com")!
        XCTAssertEqual(url1, url2)
        XCTAssertEqual(url1.url.absoluteString, "wss://jb55.com")
    }

}
