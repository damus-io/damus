//
//  NotificationsDisplayedCacheTests.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2023-11-22.
//

import Foundation
import XCTest
@testable import damus

final class NotificationsDisplayedCacheTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func test_basic_functionality() throws {
        let test_note_id_1 = NoteId(hex: "e60b9f7e00462cff647b1f1fc2fbd2ee35e82500ca85b111ac7222e5dff944ea")!
        let test_note_id_2 = NoteId(hex: "ff00ff00ff462cff647b1f1fc2fbd2ee35e82500ca85b111ac7222e5dff944ea")!
        var test_cache = NotificationsDisplayedCache(defaults: .standard)
        
        test_cache.clear_all()
        
        XCTAssertFalse(test_cache.check_and_register(note_id: test_note_id_1))
        XCTAssertTrue(test_cache.check_and_register(note_id: test_note_id_1))
        XCTAssertFalse(test_cache.check_and_register(note_id: test_note_id_2))
        XCTAssertTrue(test_cache.check_and_register(note_id: test_note_id_2))
        
        test_cache.clear_all()
    }
    
    func test_clear_all() throws {
        let test_note_id_1 = NoteId(hex: "e60b9f7e00462cff647b1f1fc2fbd2ee35e82500ca85b111ac7222e5dff944ea")!
        var test_cache = NotificationsDisplayedCache(defaults: .standard)
        
        test_cache.clear_all()
        XCTAssertFalse(test_cache.check_and_register(note_id: test_note_id_1))
        test_cache.clear_all()
        XCTAssertFalse(test_cache.check_and_register(note_id: test_note_id_1))
        test_cache.clear_all()
    }
    
    func test_auto_purge() throws {
        let test_note_id_1 = NoteId(hex: "e60b9f7e00462cff647b1f1fc2fbd2ee35e82500ca85b111ac7222e5dff944ea")!
        var test_cache = NotificationsDisplayedCache(
            defaults: .standard,
            time_to_live: 1     // Set this to be very low to make the test fast
        )
        
        XCTAssertFalse(test_cache.check_and_register(note_id: test_note_id_1))
        sleep(2)    // Use of `sleep` is ok in this context as we are specifically testing what happens after this time
        XCTAssertFalse(test_cache.check_and_register(note_id: test_note_id_1))
        
        test_cache.clear_all()
    }
}
