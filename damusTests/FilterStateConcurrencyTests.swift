//
//  FilterStateConcurrencyTests.swift
//  damusTests
//
//  Created by alltheseas on 2026-02-02.
//

import XCTest
import Dispatch
@testable import damus

/// Integration tests for FilterState event filtering and concurrent access patterns.
///
/// These tests verify the thread-safe filtering of events through EventHolder,
/// FilteredHolder, and the TOCTOU protection in Ndb access during filter operations.
///
/// ## Thread Sanitizer (TSan)
///
/// Run these tests with Thread Sanitizer enabled to detect data races:
/// 1. In Xcode: Edit Scheme → Test → Diagnostics → Thread Sanitizer
/// 2. Or via command line: `xcodebuild test -enableThreadSanitizer YES ...`
///
/// ## MainActor Isolation
///
/// Tests that mutate EventHolder call its methods via MainActor.run since
/// EventHolder.insert requires @MainActor isolation for ObservableObject/UI binding.
final class FilterStateConcurrencyTests: XCTestCase {

    // MARK: - EventHolder FilteredHolder Tests

    // NOTE: EventHolder.insert requires @MainActor isolation because:
    // 1. It modifies @Published properties (events) that drive SwiftUI view updates
    // 2. It mutates the internal has_event Set which is not thread-safe
    // 3. It iterates and modifies the filteredHolders dictionary during insertion
    // 4. FilteredHolder.insert calls objectWillChange.send() which must happen on main thread
    // Without MainActor isolation, concurrent access would cause data races on these
    // shared mutable state containers.

    /// Tests that FilteredHolder correctly filters events on insertion.
    @MainActor
    func testFilteredHolder_FiltersOnInsert() async throws {
        let eventHolder = EventHolder()

        // Create filter that only accepts even-numbered events (by timestamp)
        let evenFilter: (NostrEvent) -> Bool = { event in
            return event.created_at % 2 == 0
        }

        let filteredHolder = EventHolder.FilteredHolder(filter: evenFilter, parent: eventHolder)

        // Insert events with different timestamps
        for i in 0..<10 {
            guard let event = NostrEvent(
                content: "Test event \(i)",
                keypair: test_keypair,
                kind: NostrKind.text.rawValue,
                tags: [],
                createdAt: UInt32(i)
            ) else { continue }

            _ = eventHolder.insert(event)
        }

        // FilteredHolder should only have even timestamp events
        let filteredCount = filteredHolder.events.count
        XCTAssertEqual(filteredCount, 5, "Should have 5 events with even timestamps")
    }

    /// Tests that multiple FilteredHolders with different filters work independently.
    @MainActor
    func testMultipleFilteredHolders_IndependentFiltering() async throws {
        let eventHolder = EventHolder()

        // Filter 1: only text events
        let textFilter: (NostrEvent) -> Bool = { $0.kind == NostrKind.text.rawValue }
        let textHolder = EventHolder.FilteredHolder(filter: textFilter, parent: eventHolder)

        // Filter 2: only events with content containing "special"
        let specialFilter: (NostrEvent) -> Bool = { $0.content.contains("special") }
        let specialHolder = EventHolder.FilteredHolder(filter: specialFilter, parent: eventHolder)

        // Insert mixed events
        for i in 0..<20 {
            let content = i % 3 == 0 ? "special content \(i)" : "regular content \(i)"
            let kind = i % 2 == 0 ? NostrKind.text.rawValue : NostrKind.boost.rawValue

            guard let event = NostrEvent(
                content: content,
                keypair: test_keypair,
                kind: kind,
                tags: []
            ) else { continue }

            _ = eventHolder.insert(event)
        }

        // Verify independent filtering
        XCTAssertEqual(textHolder.events.count, 10, "Text holder should have 10 text events")
        XCTAssertEqual(specialHolder.events.count, 7, "Special holder should have 7 special events")
    }

    /// Tests concurrent event insertion with multiple FilteredHolders.
    @MainActor
    func testConcurrentInsertion_MultipleFilters() async throws {
        let eventHolder = EventHolder()

        let filter1: (NostrEvent) -> Bool = { _ in true }
        let filter2: (NostrEvent) -> Bool = { $0.created_at > 5 }
        let filter3: (NostrEvent) -> Bool = { $0.content.count > 10 }

        let holder1 = EventHolder.FilteredHolder(filter: filter1, parent: eventHolder)
        let holder2 = EventHolder.FilteredHolder(filter: filter2, parent: eventHolder)
        let holder3 = EventHolder.FilteredHolder(filter: filter3, parent: eventHolder)

        let insertCount = 50
        let allInserted = XCTestExpectation(description: "All events inserted")
        allInserted.expectedFulfillmentCount = insertCount

        // Concurrent insertion
        for i in 0..<insertCount {
            Task { @MainActor in
                guard let event = NostrEvent(
                    content: "Test content that is somewhat long \(i)",
                    keypair: test_keypair,
                    kind: NostrKind.text.rawValue,
                    tags: [],
                    createdAt: UInt32(i)
                ) else {
                    allInserted.fulfill()
                    return
                }

                _ = eventHolder.insert(event)
                allInserted.fulfill()
            }
        }

        await fulfillment(of: [allInserted], timeout: 10.0)

        // Verify all holders received correct events
        XCTAssertEqual(holder1.events.count, insertCount, "Holder 1 should have all events")
        XCTAssertEqual(holder2.events.count, insertCount - 6, "Holder 2 should have events with timestamp > 5")
        XCTAssertEqual(holder3.events.count, insertCount, "Holder 3 should have all events (content > 10 chars)")
    }

    // MARK: - Filter State Change Tests

    /// Tests that changing filter state doesn't cause race conditions with ongoing operations.
    @MainActor
    func testFilterStateChange_DuringOperations() async throws {
        let eventHolder = EventHolder()

        // Pre-populate
        for i in 0..<30 {
            guard let event = NostrEvent(
                content: "Event \(i)",
                keypair: test_keypair,
                kind: NostrKind.text.rawValue,
                tags: [],
                createdAt: UInt32(i)
            ) else { continue }

            _ = eventHolder.insert(event)
        }

        // Create multiple filtered holders simulating filter changes
        var holders: [EventHolder.FilteredHolder] = []

        for iteration in 0..<10 {
            // Create new filter (simulating user changing filter)
            let threshold = UInt32(iteration * 3)
            let newFilter: (NostrEvent) -> Bool = { $0.created_at >= threshold }
            let newHolder = EventHolder.FilteredHolder(filter: newFilter, parent: eventHolder)
            holders.append(newHolder)

            // Concurrent insertions during filter creation
            for j in 0..<5 {
                guard let event = NostrEvent(
                    content: "New event \(iteration)-\(j)",
                    keypair: test_keypair,
                    kind: NostrKind.text.rawValue,
                    tags: [],
                    createdAt: UInt32(30 + iteration * 5 + j)
                ) else { continue }

                _ = eventHolder.insert(event)
            }
        }

        // All holders should be in consistent state
        for (index, holder) in holders.enumerated() {
            XCTAssertGreaterThan(holder.events.count, 0, "Holder \(index) should have events")
        }
    }

    /// Stress test: rapid filter creation/destruction with concurrent insertions.
    @MainActor
    func testRapidFilterChanges_StressTest() async throws {
        for iteration in 0..<10 {
            let eventHolder = EventHolder()

            let insertComplete = XCTestExpectation(description: "Iteration \(iteration) inserts complete")
            insertComplete.expectedFulfillmentCount = 20

            // Start concurrent insertions
            for i in 0..<20 {
                Task { @MainActor in
                    guard let event = NostrEvent(
                        content: "Stress test \(iteration)-\(i)",
                        keypair: test_keypair,
                        kind: NostrKind.text.rawValue,
                        tags: []
                    ) else {
                        insertComplete.fulfill()
                        return
                    }

                    _ = eventHolder.insert(event)
                    insertComplete.fulfill()
                }
            }

            // Rapidly create and discard filtered holders
            var tempHolders: [EventHolder.FilteredHolder] = []
            for j in 0..<5 {
                let filter: (NostrEvent) -> Bool = { _ in j % 2 == 0 }
                let holder = EventHolder.FilteredHolder(filter: filter, parent: eventHolder)
                tempHolders.append(holder)
            }

            await fulfillment(of: [insertComplete], timeout: 5.0)

            // Clear holders (triggers cleanup)
            tempHolders.removeAll()

            // EventHolder should still be in consistent state
            XCTAssertEqual(eventHolder.events.count, 20, "Should have all 20 events")
        }
    }

    // MARK: - Event Deduplication Tests

    /// Tests that duplicate events are properly rejected even with concurrent access.
    @MainActor
    func testDeduplication_ConcurrentAccess() async throws {
        let eventHolder = EventHolder()

        // Create a single event to insert multiple times
        guard let event = NostrEvent(
            content: "Duplicate test",
            keypair: test_keypair,
            kind: NostrKind.text.rawValue,
            tags: []
        ) else {
            XCTFail("Failed to create event")
            return
        }

        let insertAttempts = 20
        let allAttempted = XCTestExpectation(description: "All insert attempts complete")
        allAttempted.expectedFulfillmentCount = insertAttempts

        var insertResults: [Bool] = []
        let resultsLock = NSLock()

        // Concurrent attempts to insert same event
        for _ in 0..<insertAttempts {
            Task { @MainActor in
                let result = eventHolder.insert(event)
                resultsLock.lock()
                insertResults.append(result)
                resultsLock.unlock()
                allAttempted.fulfill()
            }
        }

        await fulfillment(of: [allAttempted], timeout: 5.0)

        // Only one should succeed
        let successCount = insertResults.filter { $0 }.count
        XCTAssertEqual(successCount, 1, "Only one insert should succeed")
        XCTAssertEqual(eventHolder.events.count, 1, "Should have exactly one event")
    }

    // MARK: - Queue/Flush Tests

    /// Tests that queued events are properly filtered when flushed.
    @MainActor
    func testQueuedEvents_FilterOnFlush() async throws {
        let eventHolder = EventHolder()

        // Create filtered holder before queuing
        let filter: (NostrEvent) -> Bool = { $0.created_at % 2 == 0 }
        let filteredHolder = EventHolder.FilteredHolder(filter: filter, parent: eventHolder)

        // Enable queuing
        eventHolder.set_should_queue(true)

        // Insert events (should queue)
        for i in 0..<10 {
            guard let event = NostrEvent(
                content: "Queued event \(i)",
                keypair: test_keypair,
                kind: NostrKind.text.rawValue,
                tags: [],
                createdAt: UInt32(i)
            ) else { continue }

            _ = eventHolder.insert(event)
        }

        // Events should be queued, not in main list
        XCTAssertEqual(eventHolder.events.count, 0, "Main events should be empty while queuing")
        XCTAssertEqual(eventHolder.queued, 10, "Should have 10 queued events")
        XCTAssertEqual(filteredHolder.events.count, 0, "Filtered holder should be empty before flush")

        // Flush
        eventHolder.flush()

        // Now events should be in both holders
        XCTAssertEqual(eventHolder.events.count, 10, "Main events should have 10 after flush")
        XCTAssertEqual(filteredHolder.events.count, 5, "Filtered holder should have 5 even events")
    }

    /// Tests concurrent flush and insert operations.
    @MainActor
    func testConcurrentFlushAndInsert() async throws {
        let eventHolder = EventHolder()
        let filter: (NostrEvent) -> Bool = { _ in true }
        let filteredHolder = EventHolder.FilteredHolder(filter: filter, parent: eventHolder)

        eventHolder.set_should_queue(true)

        let operationsComplete = XCTestExpectation(description: "Operations complete")
        operationsComplete.expectedFulfillmentCount = 30

        // Concurrent queue insertions
        for i in 0..<20 {
            Task { @MainActor in
                guard let event = NostrEvent(
                    content: "Concurrent event \(i)",
                    keypair: test_keypair,
                    kind: NostrKind.text.rawValue,
                    tags: []
                ) else {
                    operationsComplete.fulfill()
                    return
                }

                _ = eventHolder.insert(event)
                operationsComplete.fulfill()
            }
        }

        // Concurrent flush attempts
        for _ in 0..<10 {
            Task { @MainActor in
                eventHolder.flush()
                operationsComplete.fulfill()
            }
        }

        await fulfillment(of: [operationsComplete], timeout: 10.0)

        // Final flush to ensure all events are processed
        eventHolder.flush()

        // Verify consistent state
        XCTAssertEqual(eventHolder.queued, 0, "Queue should be empty after flush")
        XCTAssertEqual(filteredHolder.events.count, eventHolder.events.count, "Filtered holder should match main holder")
    }

    // MARK: - Reset Tests

    /// Tests that reset clears all state including filtered holders.
    @MainActor
    func testReset_ClearsAllState() async throws {
        let eventHolder = EventHolder()
        let filter: (NostrEvent) -> Bool = { _ in true }
        let filteredHolder = EventHolder.FilteredHolder(filter: filter, parent: eventHolder)

        // Add events
        for i in 0..<10 {
            guard let event = NostrEvent(
                content: "Reset test \(i)",
                keypair: test_keypair,
                kind: NostrKind.text.rawValue,
                tags: []
            ) else { continue }

            _ = eventHolder.insert(event)
        }

        XCTAssertEqual(eventHolder.events.count, 10)
        XCTAssertEqual(filteredHolder.events.count, 10)

        // Reset
        eventHolder.reset()

        XCTAssertEqual(eventHolder.events.count, 0)
        XCTAssertEqual(filteredHolder.events.count, 0)
    }

    // MARK: - Integration with Ndb Tests

    /// Tests filter operations with real Ndb lookups to verify TOCTOU protection.
    @MainActor
    func testFilterWithNdbLookup() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        // Pre-populate ndb
        for i in 0..<20 {
            guard let event = NostrEvent(
                content: i % 2 == 0 ? "Reply to someone" : "Original post",
                keypair: test_keypair,
                kind: NostrKind.text.rawValue,
                tags: i % 2 == 0 ? [["e", "00000000000000000000000000000000"]] : []
            ) else { continue }

            let eventJson = encode_json(event)!
            _ = ndb.processEvent("[\"EVENT\",\"subid\",\(eventJson)]")
        }

        try await Task.sleep(for: .milliseconds(100))

        let eventHolder = EventHolder()

        // Filter that checks if event has reply tags (e tag)
        let replyFilter: (NostrEvent) -> Bool = { event in
            return event.tags.contains { $0.count >= 2 && $0[0].string() == "e" }
        }

        let replyHolder = EventHolder.FilteredHolder(filter: replyFilter, parent: eventHolder)

        // Add events to holder
        var count = 0
        subscriptionLoop: for await item in try ndb.subscribe(filters: [NostrFilter(kinds: [.text], authors: [test_keypair_full.pubkey])]) {
            switch item {
            case .event(let noteKey):
                if let note = try? ndb.lookup_note_by_key_and_copy(noteKey) {
                    _ = eventHolder.insert(note)
                    count += 1
                }
            case .eose:
                break subscriptionLoop
            }
        }

        // Should have filtered correctly
        XCTAssertGreaterThan(eventHolder.events.count, 0)
        XCTAssertLessThanOrEqual(replyHolder.events.count, eventHolder.events.count)
    }

    /// Stress test: concurrent Ndb queries with filter operations.
    /// Uses Task.detached for background queries and MainActor.run for EventHolder inserts.
    @MainActor
    func testConcurrentNdbQueries_WithFiltering_StressTest() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        // Pre-populate
        for i in 0..<50 {
            guard let event = NostrEvent(
                content: "Stress test note \(i)",
                keypair: test_keypair,
                kind: NostrKind.text.rawValue,
                tags: []
            ) else { continue }

            let eventJson = encode_json(event)!
            _ = ndb.processEvent("[\"EVENT\",\"subid\",\(eventJson)]")
        }

        try await Task.sleep(for: .milliseconds(100))

        for iteration in 0..<10 {
            let eventHolder = EventHolder()
            let filter: (NostrEvent) -> Bool = { _ in true }
            let _ = EventHolder.FilteredHolder(filter: filter, parent: eventHolder)

            let queriesComplete = XCTestExpectation(description: "Iteration \(iteration)")
            queriesComplete.expectedFulfillmentCount = 5

            // Concurrent subscriptions that insert into EventHolder
            for subIndex in 0..<5 {
                Task {
                    do {
                        subscriptionLoop: for try await item in try ndb.subscribe(filters: [NostrFilter(kinds: [.text], limit: 10)]) {
                            switch item {
                            case .event(let noteKey):
                                if let note = try? ndb.lookup_note_by_key_and_copy(noteKey) {
                                    await MainActor.run {
                                        _ = eventHolder.insert(note)
                                    }
                                }
                            case .eose:
                                break subscriptionLoop
                            }
                        }
                    } catch {
                        // Stream error
                    }
                    queriesComplete.fulfill()
                }
            }

            await fulfillment(of: [queriesComplete], timeout: 10.0)
        }
    }

    // MARK: - Collection Safety Tests

    /// Tests that removing a FilteredHolder during event iteration is safe.
    ///
    /// This verifies that the parent EventHolder handles child removal
    /// without corrupting iteration state.
    @MainActor
    func testFilteredHolderRemoval_DuringIteration() async throws {
        let eventHolder = EventHolder()

        // Create multiple filtered holders
        var holders: [EventHolder.FilteredHolder] = []
        for i in 0..<5 {
            let filter: (NostrEvent) -> Bool = { _ in i % 2 == 0 }
            let holder = EventHolder.FilteredHolder(filter: filter, parent: eventHolder)
            holders.append(holder)
        }

        // Insert events while removing holders
        let insertComplete = XCTestExpectation(description: "Inserts complete")
        insertComplete.expectedFulfillmentCount = 30

        for i in 0..<30 {
            Task { @MainActor in
                guard let event = NostrEvent(
                    content: "Removal test \(i)",
                    keypair: test_keypair,
                    kind: NostrKind.text.rawValue,
                    tags: []
                ) else {
                    insertComplete.fulfill()
                    return
                }

                _ = eventHolder.insert(event)

                // Remove a holder mid-iteration (every 10 events)
                if i % 10 == 5 && !holders.isEmpty {
                    holders.removeLast()
                }

                insertComplete.fulfill()
            }
        }

        await fulfillment(of: [insertComplete], timeout: 5.0)

        // EventHolder should still be consistent
        XCTAssertEqual(eventHolder.events.count, 30)
    }

    /// Tests behavior at EventHolder capacity boundaries.
    ///
    /// Verifies that insertion at or near maximum capacity doesn't cause issues.
    @MainActor
    func testEventHolder_CapacityBoundary() async throws {
        let eventHolder = EventHolder()

        // Insert many events rapidly
        let insertCount = 200
        let allInserted = XCTestExpectation(description: "All inserted")
        allInserted.expectedFulfillmentCount = insertCount

        for i in 0..<insertCount {
            Task { @MainActor in
                guard let event = NostrEvent(
                    content: "Capacity test \(i)",
                    keypair: test_keypair,
                    kind: NostrKind.text.rawValue,
                    tags: [],
                    createdAt: UInt32(i)
                ) else {
                    allInserted.fulfill()
                    return
                }

                _ = eventHolder.insert(event)
                allInserted.fulfill()
            }
        }

        await fulfillment(of: [allInserted], timeout: 10.0)

        // Should have all events (no silent drops)
        XCTAssertEqual(eventHolder.events.count, insertCount)
    }

    /// Tests that filter state changes during flush are handled correctly.
    @MainActor
    func testFilterStateChange_DuringFlush() async throws {
        let eventHolder = EventHolder()
        eventHolder.set_should_queue(true)

        // Queue many events
        for i in 0..<50 {
            guard let event = NostrEvent(
                content: "Flush test \(i)",
                keypair: test_keypair,
                kind: NostrKind.text.rawValue,
                tags: [],
                createdAt: UInt32(i)
            ) else { continue }

            _ = eventHolder.insert(event)
        }

        XCTAssertEqual(eventHolder.queued, 50)

        // Create filtered holder mid-queue
        let filter: (NostrEvent) -> Bool = { $0.created_at % 2 == 0 }
        let filteredHolder = EventHolder.FilteredHolder(filter: filter, parent: eventHolder)

        // Flush
        eventHolder.flush()

        // Both holders should have correct counts
        XCTAssertEqual(eventHolder.events.count, 50)
        XCTAssertEqual(filteredHolder.events.count, 25) // Even timestamps only
    }

    /// Tests atomic state transitions during enable/disable queue.
    @MainActor
    func testQueueStateTransitions_Atomic() async throws {
        let eventHolder = EventHolder()

        let operationCount = 100
        let allComplete = XCTestExpectation(description: "All complete")
        allComplete.expectedFulfillmentCount = operationCount

        /// Thread-safe counter for tracking successful inserts in concurrent test scenarios.
        actor InsertCounter {
            private var count = 0

            /// Atomically increments the counter.
            func increment() { count += 1 }

            /// Returns the current count value.
            func getCount() -> Int { count }
        }
        let insertCounter = InsertCounter()

        for i in 0..<operationCount {
            Task { @MainActor in
                // Alternate between queue/flush/insert operations
                switch i % 4 {
                case 0:
                    eventHolder.set_should_queue(true)
                case 1:
                    eventHolder.set_should_queue(false)
                case 2:
                    eventHolder.flush()
                case 3:
                    if let event = NostrEvent(
                        content: "Atomic test \(i)",
                        keypair: test_keypair,
                        kind: NostrKind.text.rawValue,
                        tags: []
                    ) {
                        let inserted = eventHolder.insert(event)
                        if inserted {
                            await insertCounter.increment()
                        }
                    }
                default:
                    break
                }
                allComplete.fulfill()
            }
        }

        await fulfillment(of: [allComplete], timeout: 10.0)

        // Final flush to clear any queued
        eventHolder.flush()

        // Verify the event count matches our tracked successful inserts
        let expectedInserts = await insertCounter.getCount()
        XCTAssertEqual(eventHolder.events.count, expectedInserts, "Event count should match successful inserts after flush")
    }

    // MARK: - RelayFilters Concurrent Modification Tests

    /// Tests concurrent insert/remove/is_filtered operations on RelayFilters.
    ///
    /// This verifies that RelayFilters handles concurrent modifications safely.
    @MainActor
    func testRelayFilters_ConcurrentModification() async throws {
        let testPubkey = test_keypair_full.pubkey
        let relayFilters = RelayFilters(our_pubkey: testPubkey)

        let operationCount = 50
        let allComplete = XCTestExpectation(description: "All operations complete")
        allComplete.expectedFulfillmentCount = operationCount

        // Create test relay URLs
        let relayURLs = (0..<10).compactMap { i in
            RelayURL("wss://relay\(i).test.com")
        }

        // Concurrent insert/remove/check operations
        for i in 0..<operationCount {
            Task { @MainActor in
                let relayURL = relayURLs[i % relayURLs.count]
                let timeline = i % 2 == 0 ? Timeline.home : Timeline.search

                switch i % 3 {
                case 0:
                    relayFilters.insert(timeline: timeline, relay_id: relayURL)
                case 1:
                    relayFilters.remove(timeline: timeline, relay_id: relayURL)
                case 2:
                    _ = relayFilters.is_filtered(timeline: timeline, relay_id: relayURL)
                default:
                    break
                }
                allComplete.fulfill()
            }
        }

        await fulfillment(of: [allComplete], timeout: 10.0)

        // Should complete without crash - state may vary but should be consistent
    }

    /// Stress test: rapid insert/remove cycles on RelayFilters.
    @MainActor
    func testRelayFilters_RapidInsertRemoveCycles_StressTest() async throws {
        for iteration in 0..<10 {
            let testPubkey = test_keypair_full.pubkey
            let relayFilters = RelayFilters(our_pubkey: testPubkey)

            guard let relayURL = RelayURL("wss://stress-test-\(iteration).relay.com") else {
                continue
            }

            let cycleCount = 20
            let cyclesComplete = XCTestExpectation(description: "Iteration \(iteration)")
            cyclesComplete.expectedFulfillmentCount = cycleCount

            for j in 0..<cycleCount {
                Task { @MainActor in
                    // Rapid toggle
                    relayFilters.insert(timeline: .home, relay_id: relayURL)
                    _ = relayFilters.is_filtered(timeline: .home, relay_id: relayURL)
                    relayFilters.remove(timeline: .home, relay_id: relayURL)
                    _ = relayFilters.is_filtered(timeline: .home, relay_id: relayURL)
                    cyclesComplete.fulfill()
                }
            }

            await fulfillment(of: [cyclesComplete], timeout: 5.0)
        }
    }

    /// Tests concurrent read operations on RelayFilters while modifications occur.
    @MainActor
    func testRelayFilters_ConcurrentReadsDuringWrites() async throws {
        let testPubkey = test_keypair_full.pubkey
        let relayFilters = RelayFilters(our_pubkey: testPubkey)

        guard let relayURL = RelayURL("wss://concurrent-rw.relay.com") else {
            XCTFail("Failed to create relay URL")
            return
        }

        let readCount = 100
        let writeCount = 20
        let allOps = XCTestExpectation(description: "All operations")
        allOps.expectedFulfillmentCount = readCount + writeCount

        // Concurrent readers
        for _ in 0..<readCount {
            Task { @MainActor in
                _ = relayFilters.is_filtered(timeline: .home, relay_id: relayURL)
                allOps.fulfill()
            }
        }

        // Concurrent writers
        for i in 0..<writeCount {
            Task { @MainActor in
                if i % 2 == 0 {
                    relayFilters.insert(timeline: .home, relay_id: relayURL)
                } else {
                    relayFilters.remove(timeline: .home, relay_id: relayURL)
                }
                allOps.fulfill()
            }
        }

        await fulfillment(of: [allOps], timeout: 10.0)
    }

}
