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
    
    func testTrimsExpiredEntriesOnLoad() async throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tmpURL)
        }
        
        var stale = PendingPost(event: makeEvent(label: "stale"))
        stale.updatedAt = Date().addingTimeInterval(-(60 * 60 * 24 * 8))
        let fresh = PendingPost(event: makeEvent(label: "fresh"))
        
        let data = try JSONEncoder().encode([stale, fresh])
        try data.write(to: tmpURL)
        
        let store = PendingPostStore(fileURL: tmpURL)
        try await Task.sleep(nanoseconds: 200_000_000)
        
        XCTAssertEqual(store.posts.count, 1)
        XCTAssertEqual(store.posts.first?.id, fresh.id)
    }
    
    func testQueueTrimmedToMaxSize() throws {
        let tmpURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        addTeardownBlock {
            try? FileManager.default.removeItem(at: tmpURL)
        }
        
        let store = PendingPostStore(fileURL: tmpURL)
        for index in 0..<120 {
            let event = makeEvent(label: "event-\(index)")
            store.track(event: event)
        }
        
        XCTAssertEqual(store.posts.count, 100)
    }
    
    private func makeEvent(label: String) -> NostrEvent {
        NostrEvent(
            content: "pending-\(label)-\(UUID().uuidString)",
            keypair: jack_keypair,
            createdAt: UInt32(Date().timeIntervalSince1970)
        )!
    }
}
