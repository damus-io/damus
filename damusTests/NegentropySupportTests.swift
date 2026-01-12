//
//  NegentropySupportTests.swift
//  damus
//
//  Created by Daniel D’Aquino on 2026-01-12.
//

import XCTest
import NostrSDK
import Negentropy
@testable import damus

final class NegentropySupportTests: XCTestCase {
    
    // MARK: - Helper Functions
    
    /// Creates and runs a local relay on the specified port.
    /// - Parameter port: The port number to run the relay on
    /// - Returns: The running LocalRelay instance
    private func setupRelay(port: UInt16) async throws -> LocalRelay {
        let builder = RelayBuilder().port(port: port)
        let relay = LocalRelay(builder: builder)
        try await relay.run()
        print("Relay url: \(await relay.url())")
        return relay
    }
    
    /// Connects to a relay and waits for the connection to be established.
    /// - Parameters:
    ///   - url: The relay URL to connect to
    ///   - label: Optional label for logging (e.g., "Relay1", "Relay2")
    /// - Returns: The connected RelayConnection instance
    private func connectToRelay(url: RelayURL, label: String = "") async -> RelayConnection {
        var connectionContinuation: CheckedContinuation<Void, Never>?
        
        let relayConnection = RelayConnection(url: url, handleEvent: { _ in }, processUnverifiedWSEvent: { wsEvent in
            let prefix = label.isEmpty ? "" : "(\(label)) "
            switch wsEvent {
            case .connected:
                connectionContinuation?.resume()
            case .message(let message):
                print("NEGENTROPY_SUPPORT_TEST \(prefix): Received: \(message)")
            case .disconnected(let closeCode, let string):
                print("NEGENTROPY_SUPPORT_TEST \(prefix): Disconnected: \(closeCode); \(String(describing: string))")
            case .error(let error):
                print("NEGENTROPY_SUPPORT_TEST \(prefix): Received error: \(error)")
            }
        })
        relayConnection.connect()
        
        // Wait for connection to be established
        await withCheckedContinuation { continuation in
            connectionContinuation = continuation
        }
        
        return relayConnection
    }
    
    /// Sends events to a relay connection.
    /// - Parameters:
    ///   - events: Array of NostrEvent to send
    ///   - connection: The RelayConnection to send events through
    private func sendEvents(_ events: [NostrEvent], to connection: RelayConnection) {
        for event in events {
            connection.send(.typical(.event(event)))
        }
    }
    
    /// Sets up a relay pool with the specified relay URLs.
    /// - Parameter urls: Array of RelayURL to add to the pool
    /// - Returns: Configured and connected RelayPool
    private func setupRelayPool(with urls: [RelayURL]) async throws -> RelayPool {
        let relayPool = RelayPool(ndb: await test_damus_state.ndb)
        
        for url in urls {
            try await relayPool.add_relay(.init(url: url, info: .readWrite))
        }
        
        await relayPool.connect()
        // Wait for relay pool to be ready.
        // It's generally not a good idea to hard code delays but RelayPool does not seem to provide any way to await for the connection to fully go through,
        // or that mechanism is not well documented.
        try await Task.sleep(for: .seconds(2))
        
        return relayPool
    }
    
    /// Runs a negentropy subscribe operation and fulfills expectations based on received events.
    /// - Parameters:
    ///   - relayPool: The relay pool to subscribe through
    ///   - filters: The NostrFilters to apply
    ///   - vector: The NegentropyStorageVector representing local state
    ///   - eventExpectations: Dictionary mapping event IDs to their expectations
    ///   - ignoreUnsupportedRelays: Whether to ignore relays that don't support negentropy
    private func runNegentropySubscribe(
        relayPool: RelayPool,
        filters: [NostrFilter],
        vector: NegentropyStorageVector,
        eventExpectations: [NoteId: XCTestExpectation],
        ignoreUnsupportedRelays: Bool = false
    ) {
        Task {
            do {
                for try await item in try await relayPool.negentropySubscribe(
                    filters: filters,
                    negentropyVector: vector,
                    ignoreUnsupportedRelays: ignoreUnsupportedRelays
                ) {
                    switch item {
                    case .event(let event):
                        if let expectation = eventExpectations[event.id] {
                            expectation.fulfill()
                        }
                    case .eose:
                        return
                    }
                }
            }
            catch {
                XCTFail("Stream Error: \(error)")
            }
        }
    }
    
    // MARK: - Test Cases
    
    func testBasic() async throws {
        // Given: A relay with noteA and noteB, and local storage has noteA
        let relay = try await setupRelay(port: 8080)    // Do not discard the result to avoid relay from being garbage collected and shutdown
        let relayUrl = RelayURL(await relay.url().description)!
        
        let noteA = NostrEvent(content: "A", keypair: test_keypair)!
        let noteB = NostrEvent(content: "B", keypair: test_keypair)!
        
        let relayConnection = await connectToRelay(url: relayUrl)
        sendEvents([noteA, noteB], to: relayConnection)
        
        let relayPool = try await setupRelayPool(with: [relayUrl])
        
        let negentropyVector = NegentropyStorageVector()
        try negentropyVector.insert(nostrEvent: noteA)
        
        let getsNoteB = XCTestExpectation(description: "Gets note B")
        let doesNotGetNoteA = XCTestExpectation(description: "Does not get note A")
        doesNotGetNoteA.isInverted = true
        
        // When: Performing negentropy subscribe
        runNegentropySubscribe(
            relayPool: relayPool,
            filters: [NostrFilter(kinds: [.text])],
            vector: negentropyVector,
            eventExpectations: [noteA.id: doesNotGetNoteA, noteB.id: getsNoteB]
        )
        
        // Then: Should receive only noteB (noteA is already synced)
        await fulfillment(of: [getsNoteB, doesNotGetNoteA], timeout: 5.0)
    }
    
    func testEmptyLocalStorage() async throws {
        // Given: A relay with noteA and noteB, and empty local storage
        let relay = try await setupRelay(port: 8081)
        let relayUrl = RelayURL(await relay.url().description)!
        
        let noteA = NostrEvent(content: "A", keypair: test_keypair)!
        let noteB = NostrEvent(content: "B", keypair: test_keypair)!
        
        let relayConnection = await connectToRelay(url: relayUrl)
        sendEvents([noteA, noteB], to: relayConnection)
        
        let relayPool = try await setupRelayPool(with: [relayUrl])
        
        // Empty negentropy vector - should receive all events
        let negentropyVector = NegentropyStorageVector()
        
        let getsNoteA = XCTestExpectation(description: "Gets note A")
        let getsNoteB = XCTestExpectation(description: "Gets note B")
        
        // When: Performing negentropy subscribe with empty local storage
        runNegentropySubscribe(
            relayPool: relayPool,
            filters: [NostrFilter(kinds: [.text])],
            vector: negentropyVector,
            eventExpectations: [noteA.id: getsNoteA, noteB.id: getsNoteB]
        )
        
        // Then: Should receive all events (noteA and noteB)
        await fulfillment(of: [getsNoteA, getsNoteB], timeout: 5.0)
    }
    
    /// Test negentropy sync with two relays having overlapping events.
    /// Relay1 has noteA+noteB, Relay2 has noteB+noteC, local has noteB.
    /// Should get noteA from Relay1 and noteC from Relay2 (deduplicating noteB).
    func testTwoRelaysWithOverlap() async throws {
        // Given: Two relays with overlapping events and local storage has noteB
        let relay1 = try await setupRelay(port: 8082)
        let relay2 = try await setupRelay(port: 8083)
        
        let relayUrl1 = RelayURL(await relay1.url().description)!
        let relayUrl2 = RelayURL(await relay2.url().description)!
        
        let noteA = NostrEvent(content: "A", keypair: test_keypair)!
        let noteB = NostrEvent(content: "B", keypair: test_keypair)!
        let noteC = NostrEvent(content: "C", keypair: test_keypair)!
        
        // Connect to relay1 and send noteA + noteB
        let relayConnection1 = await connectToRelay(url: relayUrl1, label: "Relay1")
        sendEvents([noteA, noteB], to: relayConnection1)
        
        // Connect to relay2 and send noteB + noteC
        let relayConnection2 = await connectToRelay(url: relayUrl2, label: "Relay2")
        sendEvents([noteB, noteC], to: relayConnection2)
        
        let relayPool = try await setupRelayPool(with: [relayUrl1, relayUrl2])
        
        // Local vector has noteB already
        let negentropyVector = NegentropyStorageVector()
        try negentropyVector.insert(nostrEvent: noteB)
        
        let getsNoteA = XCTestExpectation(description: "Gets note A")
        let getsNoteC = XCTestExpectation(description: "Gets note C")
        let doesNotGetNoteB = XCTestExpectation(description: "Does not get note B")
        doesNotGetNoteB.isInverted = true
        
        // When: Performing negentropy subscribe across two relays
        runNegentropySubscribe(
            relayPool: relayPool,
            filters: [NostrFilter(kinds: [.text])],
            vector: negentropyVector,
            eventExpectations: [noteA.id: getsNoteA, noteB.id: doesNotGetNoteB, noteC.id: getsNoteC]
        )
        
        // Then: Should receive noteA and noteC, but not noteB (already synced)
        await fulfillment(of: [getsNoteA, getsNoteC, doesNotGetNoteB], timeout: 5.0)
    }
    
    /// Test negentropy sync when all events are already synced locally.
    /// Local has noteA+noteB, relay has noteA+noteB.
    /// Should receive EOSE only without any events.
    func testAllEventsSynced() async throws {
        // Given: A relay with noteA and noteB, and local storage has both events
        let relay = try await setupRelay(port: 8084)
        let relayUrl = RelayURL(await relay.url().description)!
        
        let noteA = NostrEvent(content: "A", keypair: test_keypair)!
        let noteB = NostrEvent(content: "B", keypair: test_keypair)!
        
        let relayConnection = await connectToRelay(url: relayUrl)
        sendEvents([noteA, noteB], to: relayConnection)
        
        let relayPool = try await setupRelayPool(with: [relayUrl])
        
        // Local vector has both events already
        let negentropyVector = NegentropyStorageVector()
        try negentropyVector.insert(nostrEvent: noteA)
        try negentropyVector.insert(nostrEvent: noteB)
        
        let doesNotGetNoteA = XCTestExpectation(description: "Does not get note A")
        let doesNotGetNoteB = XCTestExpectation(description: "Does not get note B")
        doesNotGetNoteA.isInverted = true
        doesNotGetNoteB.isInverted = true
        
        // When: Performing negentropy subscribe with all events already synced
        runNegentropySubscribe(
            relayPool: relayPool,
            filters: [NostrFilter(kinds: [.text])],
            vector: negentropyVector,
            eventExpectations: [noteA.id: doesNotGetNoteA, noteB.id: doesNotGetNoteB]
        )
        
        // Then: Should not receive any events (all already synced)
        await fulfillment(of: [doesNotGetNoteA, doesNotGetNoteB], timeout: 5.0)
    }
    
    /// Test negentropy sync when local storage is a superset of relay events.
    /// Local has noteA+noteB+noteC, relay has noteA+noteB.
    /// Should receive no new events.
    func testRelaySubset() async throws {
        // Given: A relay with noteA and noteB, and local storage has noteA, noteB, and noteC
        let relay = try await setupRelay(port: 8085)
        let relayUrl = RelayURL(await relay.url().description)!
        
        let noteA = NostrEvent(content: "A", keypair: test_keypair)!
        let noteB = NostrEvent(content: "B", keypair: test_keypair)!
        let noteC = NostrEvent(content: "C", keypair: test_keypair)!
        
        let relayConnection = await connectToRelay(url: relayUrl)
        sendEvents([noteA, noteB], to: relayConnection)
        
        let relayPool = try await setupRelayPool(with: [relayUrl])
        
        // Local vector has all relay events plus one more
        let negentropyVector = NegentropyStorageVector()
        try negentropyVector.insert(nostrEvent: noteA)
        try negentropyVector.insert(nostrEvent: noteB)
        try negentropyVector.insert(nostrEvent: noteC)
        
        let doesNotGetNoteA = XCTestExpectation(description: "Does not get note A")
        let doesNotGetNoteB = XCTestExpectation(description: "Does not get note B")
        let doesNotGetNoteC = XCTestExpectation(description: "Does not get note C")
        doesNotGetNoteA.isInverted = true
        doesNotGetNoteB.isInverted = true
        doesNotGetNoteC.isInverted = true
        
        // When: Performing negentropy subscribe where local is a superset of relay
        runNegentropySubscribe(
            relayPool: relayPool,
            filters: [NostrFilter(kinds: [.text])],
            vector: negentropyVector,
            eventExpectations: [noteA.id: doesNotGetNoteA, noteB.id: doesNotGetNoteB, noteC.id: doesNotGetNoteC]
        )
        
        // Then: Should not receive any events (local has all relay events and more)
        await fulfillment(of: [doesNotGetNoteA, doesNotGetNoteB, doesNotGetNoteC], timeout: 5.0)
    }
    
    /// Test negentropy sync with three relays having overlapping events and partial local sync.
    /// Relay1 has A+B, Relay2 has B+C, Relay3 has C+D, local has A+C.
    /// Should only receive B and D.
    func testThreeRelaysPartialSync() async throws {
        // Given: Three relays with overlapping events and local storage has noteA and noteC
        let relay1 = try await setupRelay(port: 8086)
        let relay2 = try await setupRelay(port: 8087)
        let relay3 = try await setupRelay(port: 8088)
        
        let relayUrl1 = RelayURL(await relay1.url().description)!
        let relayUrl2 = RelayURL(await relay2.url().description)!
        let relayUrl3 = RelayURL(await relay3.url().description)!
        
        let noteA = NostrEvent(content: "A", keypair: test_keypair)!
        let noteB = NostrEvent(content: "B", keypair: test_keypair)!
        let noteC = NostrEvent(content: "C", keypair: test_keypair)!
        let noteD = NostrEvent(content: "D", keypair: test_keypair)!
        
        // Connect to relay1 and send noteA + noteB
        let relayConnection1 = await connectToRelay(url: relayUrl1, label: "Relay1")
        sendEvents([noteA, noteB], to: relayConnection1)
        
        // Connect to relay2 and send noteB + noteC
        let relayConnection2 = await connectToRelay(url: relayUrl2, label: "Relay2")
        sendEvents([noteB, noteC], to: relayConnection2)
        
        // Connect to relay3 and send noteC + noteD
        let relayConnection3 = await connectToRelay(url: relayUrl3, label: "Relay3")
        sendEvents([noteC, noteD], to: relayConnection3)
        
        let relayPool = try await setupRelayPool(with: [relayUrl1, relayUrl2, relayUrl3])
        
        // Local vector has noteA and noteC already
        let negentropyVector = NegentropyStorageVector()
        try negentropyVector.insert(nostrEvent: noteA)
        try negentropyVector.insert(nostrEvent: noteC)
        
        let getsNoteB = XCTestExpectation(description: "Gets note B")
        let getsNoteD = XCTestExpectation(description: "Gets note D")
        let doesNotGetNoteA = XCTestExpectation(description: "Does not get note A")
        let doesNotGetNoteC = XCTestExpectation(description: "Does not get note C")
        doesNotGetNoteA.isInverted = true
        doesNotGetNoteC.isInverted = true
        
        // When: Performing negentropy subscribe across three relays with partial overlap
        runNegentropySubscribe(
            relayPool: relayPool,
            filters: [NostrFilter(kinds: [.text])],
            vector: negentropyVector,
            eventExpectations: [
                noteA.id: doesNotGetNoteA,
                noteB.id: getsNoteB,
                noteC.id: doesNotGetNoteC,
                noteD.id: getsNoteD
            ]
        )
        
        // Then: Should receive only noteB and noteD (noteA and noteC already synced)
        await fulfillment(of: [getsNoteB, getsNoteD, doesNotGetNoteA, doesNotGetNoteC], timeout: 5.0)
    }
    
    /// Test negentropy sync with multiple filters for different event kinds across three relays.
    /// Relay1 has text notes A+B (kind 1), Relay2 has text B + DM C (kind 4), Relay3 has DMs C+D (kind 4).
    /// Local has text note A (kind 1) and DM C (kind 4).
    /// Uses two filters: one for kind 1 (text), one for kind 4 (DMs).
    /// Should only receive text note B and DM D.
    func testMultipleFiltersWithDifferentKinds() async throws {
        // Given: Three relays with mixed event kinds and local storage has text note A and DM C
        let relay1 = try await setupRelay(port: 8089)
        let relay2 = try await setupRelay(port: 8090)
        let relay3 = try await setupRelay(port: 8091)
        
        let relayUrl1 = RelayURL(await relay1.url().description)!
        let relayUrl2 = RelayURL(await relay2.url().description)!
        let relayUrl3 = RelayURL(await relay3.url().description)!
        
        // Create events with different kinds
        // kind 1 = text notes, kind 4 = encrypted DMs
        let noteA = NostrEvent(content: "A", keypair: test_keypair, kind: 1)!  // text note
        let noteB = NostrEvent(content: "B", keypair: test_keypair, kind: 1)!  // text note
        let noteC = NostrEvent(content: "C", keypair: test_keypair, kind: 4)!  // DM
        let noteD = NostrEvent(content: "D", keypair: test_keypair, kind: 4)!  // DM
        
        // Connect to relay1 and send text notes A + B
        let relayConnection1 = await connectToRelay(url: relayUrl1, label: "Relay1")
        sendEvents([noteA, noteB], to: relayConnection1)
        
        // Connect to relay2 and send text note B + DM C
        let relayConnection2 = await connectToRelay(url: relayUrl2, label: "Relay2")
        sendEvents([noteB, noteC], to: relayConnection2)
        
        // Connect to relay3 and send DMs C + D
        let relayConnection3 = await connectToRelay(url: relayUrl3, label: "Relay3")
        sendEvents([noteC, noteD], to: relayConnection3)
        
        let relayPool = try await setupRelayPool(with: [relayUrl1, relayUrl2, relayUrl3])
        
        // Local vector has text note A and DM C already
        let negentropyVector = NegentropyStorageVector()
        try negentropyVector.insert(nostrEvent: noteA)
        try negentropyVector.insert(nostrEvent: noteC)
        
        let getsNoteB = XCTestExpectation(description: "Gets text note B")
        let getsNoteD = XCTestExpectation(description: "Gets DM D")
        let doesNotGetNoteA = XCTestExpectation(description: "Does not get text note A")
        let doesNotGetNoteC = XCTestExpectation(description: "Does not get DM C")
        doesNotGetNoteA.isInverted = true
        doesNotGetNoteC.isInverted = true
        
        // When: Performing negentropy subscribe with multiple filters for different kinds
        // Use two filters: one for kind 1 (text), one for kind 4 (DMs)
        runNegentropySubscribe(
            relayPool: relayPool,
            filters: [
                NostrFilter(kinds: [.text]),           // kind 1
                NostrFilter(kinds: [.dm])              // kind 4
            ],
            vector: negentropyVector,
            eventExpectations: [
                noteA.id: doesNotGetNoteA,
                noteB.id: getsNoteB,
                noteC.id: doesNotGetNoteC,
                noteD.id: getsNoteD
            ]
        )
        
        // Then: Should receive only text note B and DM D (text note A and DM C already synced)
        await fulfillment(of: [getsNoteB, getsNoteD, doesNotGetNoteA, doesNotGetNoteC], timeout: 5.0)
    }
}
