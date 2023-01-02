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
        let locale = Locale(identifier: "en_US")
        let calendar = locale.calendar

        XCTAssertEqual(time_ago_since(Date.now, calendar), "now")
        XCTAssertEqual(time_ago_since(Date.now.addingTimeInterval(-2), calendar), "now")
        XCTAssertEqual(time_ago_since(Date.now.addingTimeInterval(-3), calendar), "3s")
        XCTAssertEqual(time_ago_since(Date.now.addingTimeInterval(-59), calendar), "59s")
        XCTAssertEqual(time_ago_since(Date.now.addingTimeInterval(-60), calendar), "1m")
        XCTAssertEqual(time_ago_since(calendar.date(byAdding: .hour, value: -1, to: Date.now)!.addingTimeInterval(1), calendar), "59m")
        XCTAssertEqual(time_ago_since(calendar.date(byAdding: .hour, value: -1, to: Date.now)!, calendar), "1h")
        XCTAssertEqual(time_ago_since(calendar.date(byAdding: .day, value: -1, to: Date.now)!.addingTimeInterval(1), calendar), "23h")
        XCTAssertEqual(time_ago_since(calendar.date(byAdding: .day, value: -1, to: Date.now)!, calendar), "1d")
        XCTAssertEqual(time_ago_since(calendar.date(byAdding: .weekOfMonth, value: -1, to: Date.now)!.addingTimeInterval(1), calendar), "6d")
        XCTAssertEqual(time_ago_since(calendar.date(byAdding: .weekOfMonth, value: -1, to: Date.now)!, calendar), "1w")
        XCTAssertEqual(time_ago_since(calendar.date(byAdding: .weekOfMonth, value: -2, to: Date.now)!, calendar), "2w")
        XCTAssertEqual(time_ago_since(calendar.date(byAdding: .weekOfMonth, value: -3, to: Date.now)!, calendar), "3w")
        // Not testing the 4-5 week boundary since how it is formatted depends on which month and year it is currently when this test executes.
        XCTAssertEqual(time_ago_since(calendar.date(byAdding: .month, value: -1, to: Date.now)!, calendar), "1mo")
        XCTAssertEqual(time_ago_since(calendar.date(byAdding: .year, value: -1, to: Date.now)!.addingTimeInterval(1), calendar), "11mo")
        XCTAssertEqual(time_ago_since(calendar.date(byAdding: .year, value: -1, to: Date.now)!, calendar), "1y")
        XCTAssertEqual(time_ago_since(calendar.date(byAdding: .year, value: -1000, to: Date.now)!, calendar), "1,000y")
    }

}
