//
//  MuteItemTests.swift
//  damusTests
//
//  Created by Charlie Fish on 1/14/24.
//

import XCTest
@testable import damus

class MuteItemTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    // MARK: - `is_expired`
    func test_hashtag_is_expired() throws {
        XCTAssertTrue(MuteItem.hashtag(Hashtag(hashtag: "test"), Date(timeIntervalSince1970: 0)).is_expired())
        XCTAssertTrue(MuteItem.hashtag(Hashtag(hashtag: "test"), .distantPast).is_expired())
        XCTAssertFalse(MuteItem.hashtag(Hashtag(hashtag: "test"), .distantFuture).is_expired())
    }
    func test_user_is_expired() throws {
        XCTAssertTrue(MuteItem.user(test_pubkey, Date(timeIntervalSince1970: 0)).is_expired())
        XCTAssertTrue(MuteItem.user(test_pubkey, .distantPast).is_expired())
        XCTAssertFalse(MuteItem.user(test_pubkey, .distantFuture).is_expired())
    }
    func test_word_is_expired() throws {
        XCTAssertTrue(MuteItem.word("test", Date(timeIntervalSince1970: 0)).is_expired())
        XCTAssertTrue(MuteItem.word("test", .distantPast).is_expired())
        XCTAssertFalse(MuteItem.word("test", .distantFuture).is_expired())
    }
    func test_thread_is_expired() throws {
        XCTAssertTrue(MuteItem.thread(test_note.id, Date(timeIntervalSince1970: 0)).is_expired())
        XCTAssertTrue(MuteItem.thread(test_note.id, .distantPast).is_expired())
        XCTAssertFalse(MuteItem.thread(test_note.id, .distantFuture).is_expired())
    }


    // MARK: - `tag`
    func test_hashtag_tag() throws {
        XCTAssertEqual(MuteItem.hashtag(Hashtag(hashtag: "test"), nil).tag, ["t", "test"])
        XCTAssertEqual(MuteItem.hashtag(Hashtag(hashtag: "test"), Date(timeIntervalSince1970: 1704067200)).tag, ["t", "test", "1704067200"])
    }
    func test_user_tag() throws {
        XCTAssertEqual(MuteItem.user(test_pubkey, Date(timeIntervalSince1970: 1704067200)).tag, ["p", test_pubkey.hex(), "1704067200"])
    }
    func test_word_tag() throws {
        XCTAssertEqual(MuteItem.word("test", Date(timeIntervalSince1970: 1704067200)).tag, ["word", "test", "1704067200"])
    }
    func test_thread_tag() throws {
        XCTAssertEqual(MuteItem.thread(test_note.id, Date(timeIntervalSince1970: 1704067200)).tag, ["e", test_note.id.hex(), "1704067200"])
    }
}
