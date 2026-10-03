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

    func testCapsAtMaxPerNote() {
        let tags = Cashtag.extract(from: "$BTC $ETH $SOL $ADA $XRP $BTC")
        XCTAssertEqual(tags.map(\.symbol), ["BTC", "ETH", "SOL"])
        XCTAssertEqual(tags.count, Cashtag.maxPerNote)
    }

    func testBelowCapUnaffected() {
        XCTAssertEqual(Cashtag.extract(from: "$BTC $ETH").map(\.symbol), ["BTC", "ETH"])
    }

    func testZeroLimit() {
        XCTAssertTrue(Cashtag.extract(from: "$BTC", limit: 0).isEmpty)
    }
}
