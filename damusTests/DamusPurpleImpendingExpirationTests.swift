//
//  DamusPurpleImpendingExpirationTests.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2024-02-26.
//

import XCTest
@testable import damus

final class DamusPurpleImpendingExpirationTests : XCTestCase {
    func testNotificationContentSetDoesNotAllowRepetition() {
        var notification_contents: Set<DamusAppNotification.Content> = []
        let expiry_date = UInt64(Date.now.timeIntervalSince1970)
        let now = Date.now
        let notification_1 = DamusAppNotification(content: .purple_impending_expiration(days_remaining: 3, expiry_date: expiry_date), timestamp: now)
        notification_contents.insert(notification_1.content)
        let notification_2 = DamusAppNotification(content: .purple_impending_expiration(days_remaining: 3, expiry_date: expiry_date), timestamp: now)
        notification_contents.insert(notification_2.content)
        let notification_3 = DamusAppNotification(content: .purple_impending_expiration(days_remaining: 2, expiry_date: expiry_date), timestamp: now)
        notification_contents.insert(notification_3.content)
        let notification_4 = DamusAppNotification(content: .purple_impending_expiration(days_remaining: 2, expiry_date: expiry_date), timestamp: now)
        notification_contents.insert(notification_4.content)
        let notification_5 = DamusAppNotification(content: .purple_impending_expiration(days_remaining: 1, expiry_date: expiry_date), timestamp: now)
        notification_contents.insert(notification_5.content)
        let notification_6 = DamusAppNotification(content: .purple_impending_expiration(days_remaining: 1, expiry_date: expiry_date), timestamp: now)
        notification_contents.insert(notification_6.content)
        XCTAssertEqual(notification_contents.count, 3)
        XCTAssertTrue(notification_contents.contains(notification_1.content))
        XCTAssertTrue(notification_contents.contains(notification_2.content))
        XCTAssertTrue(notification_contents.contains(notification_3.content))
        XCTAssertTrue(notification_contents.contains(notification_4.content))
        XCTAssertTrue(notification_contents.contains(notification_5.content))
        XCTAssertTrue(notification_contents.contains(notification_6.content))
    }
}

