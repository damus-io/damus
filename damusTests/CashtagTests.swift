//
//  CashtagTests.swift
//  damusTests
//

import XCTest
@testable import damus

final class CashtagTests: XCTestCase {

    func testExtractSingle() {
        XCTAssertEqual(Cashtag.extract(from: "buying $BTC today"), [Cashtag(symbol: "BTC")])
    }

    func testExtractMultipleDeduped() {
        let tags = Cashtag.extract(from: "$BTC vs $ETH, and $BTC again")
        XCTAssertEqual(tags.map(\.symbol), ["BTC", "ETH"])
    }

    func testIgnoresLowercaseAndNumbers() {
        XCTAssertTrue(Cashtag.extract(from: "$btc $100 $B $1BTC").isEmpty)
    }

    func testIgnoresEmbeddedDollar() {
        XCTAssertTrue(Cashtag.extract(from: "costs US$BTC lol").isEmpty)
    }

    func testPunctuationBoundary() {
        XCTAssertEqual(Cashtag.extract(from: "wen $BTC? ($ETH)").map(\.symbol), ["BTC", "ETH"])
    }
}
