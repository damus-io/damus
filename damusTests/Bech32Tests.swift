//
//  Bech32Tests.swift
//  damusTests
//
//  Created by William Casarin on 2022-05-22.
//

import XCTest
@testable import damus

class Bech32Tests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func test_bech32_encode_decode() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
        
        let pubkey = "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"
        guard let b32_pubkey = bech32_pubkey(pubkey) else {
            XCTAssert(false)
            return
        }
        
        guard let decoded = try? bech32_decode(b32_pubkey) else {
            XCTAssert(false)
            return
        }
        
        let encoded = hex_encode(decoded.data)
        
        XCTAssertEqual(encoded, pubkey)
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
