//
//  InvoiceTests.swift
//  damusTests
//
//  Created by William Casarin on 2022-10-18.
//

import XCTest
@testable import damus

final class InvoiceTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testParseInvoiceUpper() throws {
        let invstr = "LNBC100N1P357SL0SP5T9N56WDZTUN39LGDQLR30XQWKSG3K69Q4Q2RKR52APLUJW0ESN0QPP5MRQGLJK62Z20Q4NVGR6LZCYN6FHYLZCCWDVU4K77APG3ZMRKUJJQDPZW35XJUEQD9EJQCFQV3JHXCMJD9C8G6T0DCXQYJW5QCQPJRZJQT56H4GVP5YX36U2UZQA6QWCSK3E2DUUNFXPPZJ9VHYPC3WFE2WSWZ607UQQ3XQQQSQQQQQQQQQQQLQQYG9QYYSGQAGX5H20AEULJ3GDWX3KXS8U9F4MCAKDKWUAKASAMM9562FFYR9EN8YG20LG0YGNR9ZPWP68524KMDA0T5XP2WYTEX35PU8HAPYJAJXQPSQL29R"
        let parsed = parse_mentions(content: invstr, tags: [])
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertNotNil(parsed[0].is_invoice)
        guard let invoice = parsed[0].is_invoice else {
            return
        }
        XCTAssertEqual(invoice.amount, 10000)
        XCTAssertEqual(invoice.expiry, 604800)
        XCTAssertEqual(invoice.created_at, 1666139119)
        XCTAssertEqual(invoice.string, invstr)
    }
    
    func testParseInvoice() throws {
        let invstr = "lnbc100n1p357sl0sp5t9n56wdztun39lgdqlr30xqwksg3k69q4q2rkr52aplujw0esn0qpp5mrqgljk62z20q4nvgr6lzcyn6fhylzccwdvu4k77apg3zmrkujjqdpzw35xjueqd9ejqcfqv3jhxcmjd9c8g6t0dcxqyjw5qcqpjrzjqt56h4gvp5yx36u2uzqa6qwcsk3e2duunfxppzj9vhypc3wfe2wswz607uqq3xqqqsqqqqqqqqqqqlqqyg9qyysgqagx5h20aeulj3gdwx3kxs8u9f4mcakdkwuakasamm9562ffyr9en8yg20lg0ygnr9zpwp68524kmda0t5xp2wytex35pu8hapyjajxqpsql29r"
        let parsed = parse_mentions(content: invstr, tags: [])
        
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed.count, 1)
        XCTAssertNotNil(parsed[0].is_invoice)
        guard let invoice = parsed[0].is_invoice else {
            return
        }
        XCTAssertEqual(invoice.amount, 10000)
        XCTAssertEqual(invoice.expiry, 604800)
        XCTAssertEqual(invoice.created_at, 1666139119)
        XCTAssertEqual(invoice.string, invstr)
    }

}
