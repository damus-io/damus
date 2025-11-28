//
//  PendingPostStoreTests.swift
//  damusTests
//
//  Created by OpenAI Codex on 2025-01-04.
//

import XCTest
@testable import damus

@MainActor
final class PendingPostStoreTests: XCTestCase {
    
    func testTrackAndMarkSent() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tmpURL)
        }
        
        let store = PendingPostStore(fileURL: tmpURL)
        XCTAssertTrue(store.posts.isEmpty)
        
        let event = test_note
        store.track(event: event)
        XCTAssertEqual(store.posts.count, 1)
        
        store.markSent(event.id)
        
        XCTAssertTrue(store.posts.isEmpty)
    }
}
