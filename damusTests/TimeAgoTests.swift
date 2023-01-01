//
//  TimeAgoTests.swift
//  damusTests
//
//  Created by Terry Yiu on 12/30/22.
//

import XCTest
@testable import damus

final class TimeAgoTests: XCTestCase {

    func testTimeAgoSince() {
        XCTAssertEqual(time_ago_since(Date.now), "now")
        XCTAssertEqual(time_ago_since(Date.now.addingTimeInterval(-2)), "now")
        XCTAssertEqual(time_ago_since(Date.now.addingTimeInterval(-3)), "3s")
        XCTAssertEqual(time_ago_since(Date.now.addingTimeInterval(-59)), "59s")
        XCTAssertEqual(time_ago_since(Date.now.addingTimeInterval(-60)), "1m")
        XCTAssertEqual(time_ago_since(Date.now.addingTimeInterval(-3599)), "59m")
        XCTAssertEqual(time_ago_since(Date.now.addingTimeInterval(-3600)), "1h")
        XCTAssertEqual(time_ago_since(Date.now.addingTimeInterval(-86399)), "23h")
        XCTAssertEqual(time_ago_since(Date.now.addingTimeInterval(-86400)), "1d")
        XCTAssertEqual(time_ago_since(Calendar.current.date(byAdding: .weekOfMonth, value: -1, to: Date.now)!.addingTimeInterval(1)), "6d")
        XCTAssertEqual(time_ago_since(Calendar.current.date(byAdding: .weekOfMonth, value: -1, to: Date.now)!), "1w")
        XCTAssertEqual(time_ago_since(Calendar.current.date(byAdding: .weekOfMonth, value: -2, to: Date.now)!), "2w")
        XCTAssertEqual(time_ago_since(Calendar.current.date(byAdding: .weekOfMonth, value: -3, to: Date.now)!), "3w")
        // Not testing the 4-5 week boundary since how it is formatted depends on which month and year it is currently when this test executes.
        XCTAssertEqual(time_ago_since(Calendar.current.date(byAdding: .month, value: -1, to: Date.now)!), "1mo")
        XCTAssertEqual(time_ago_since(Calendar.current.date(byAdding: .year, value: -1, to: Date.now)!.addingTimeInterval(1)), "11mo")
        XCTAssertEqual(time_ago_since(Calendar.current.date(byAdding: .year, value: -1, to: Date.now)!), "1y")
        XCTAssertEqual(time_ago_since(Calendar.current.date(byAdding: .year, value: -1000, to: Date.now)!), "1,000y")
    }

}
