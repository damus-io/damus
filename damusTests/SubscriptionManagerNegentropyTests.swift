//
//  SubscriptionManagerNegentropyTests.swift
//  damus
//
//  Created by Daniel D'Aquino on 2026-01-17.
//

import XCTest
import CryptoKit
import Network
import NostrSDK
import Negentropy
@testable import damus

/// Tests for the SubscriptionManager's negentropy streaming mode functionality.
///
/// These tests verify that SubscriptionManager correctly handles negentropy-based synchronization
/// by streaming events from NostrDB first, then efficiently syncing missing events from relays
/// using the negentropy protocol.
final class SubscriptionManagerNegentropyTests: XCTestCase {
    
    // MARK: - Helper Functions
    
    /// Creates and runs a local relay on a free port.
    /// - Returns: The running LocalRelay instance
    private func setupRelay() async throws -> LocalRelay {
        try await LocalRelayTestSupport.startRelay()
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
                print("SUBSCRIPTION_MANAGER_NEGENTROPY_TEST \(prefix): Received: \(message)")
            case .disconnected(let closeCode, let string):
                print("SUBSCRIPTION_MANAGER_NEGENTROPY_TEST \(prefix): Disconnected: \(closeCode); \(String(describing: string))")
            case .error(let error):
                print("SUBSCRIPTION_MANAGER_NEGENTROPY_TEST \(prefix): Received error: \(error)")
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
    
    /// Sets up a NostrNetworkManager with the specified relay URLs.
    /// - Parameters:
    ///   - urls: Array of RelayURL to add to the manager
    ///   - ndb: The Ndb instance to use
    /// - Returns: Configured and connected NostrNetworkManager
    private func setupNetworkManager(with urls: [RelayURL], ndb: Ndb) async throws -> NostrNetworkManager {
        let delegate = TestNetworkDelegate(ndb: ndb, keypair: test_keypair, bootstrapRelays: urls)
        let networkManager = NostrNetworkManager(delegate: delegate, addNdbToRelayPool: true)
        
        // Manually add relays to the pool since we're bypassing normal initialization
        for url in urls {
            do {
                try await networkManager.userRelayList.insert(relay: .init(url: url, rwConfiguration: .readWrite), force: true)
            }
            catch {
                switch error {
                case .relayAlreadyExists: continue
                default: throw error
                }
            }
        }
        
        await networkManager.userRelayList.connect()
        // Wait for relay pool to be ready.
        // It's generally not a good idea to hard code delays but RelayPool does not seem to provide any way to await for the connection to fully go through,
        // or that mechanism is not well documented.
        try await Task.sleep(for: .seconds(2))
        
        return networkManager
    }
    
    /// Stores events in NostrDB and does not return until they are queryable.
    ///
    /// `Ndb.add(event:)` hands the note to the ingester and returns; the note only becomes visible
    /// to a *query* once that ingest commits. Every test here goes on to assert **when** an event
    /// surfaces in a stream, and a subscription's initial results come from exactly such a query
    /// (see `Ndb.subscribe(filters:maxSimultaneousResults:)`) — so without this wait the tests are
    /// racing the ingester, and a note that lost the race is reported as a streaming-order bug
    /// rather than as the setup race it is.
    /// - Parameters:
    ///   - events: Array of NostrEvent to store in NDB
    ///   - ndb: The Ndb instance to store events in
    private func storeEventsInNdb(_ events: [NostrEvent], ndb: Ndb) async throws {
        for event in events {
            do {
                try ndb.add(event: event)
            } catch {
                XCTFail("Failed to store event in NDB: \(error)")
            }
        }
        for event in events {
            try await waitUntilQueryable(event.id, in: ndb)
        }
    }

    /// Polls NostrDB until `noteId` can be found by a query, or the timeout elapses.
    private func waitUntilQueryable(_ noteId: NoteId, in ndb: Ndb, timeout: Duration = .seconds(5)) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)
        while ContinuousClock.now < deadline {
            if (try? ndb.lookup_note_key(noteId)) != nil { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for \(noteId.hex()) to become queryable in NostrDB")
    }
    
    /// Runs a subscription manager stream and fulfills expectations based on received events and EOSE signals.
    /// - Parameters:
    ///   - networkManager: The network manager to subscribe through
    ///   - filters: The NostrFilters to apply
    ///   - streamMode: The stream mode to use for subscription
    ///   - ndbEventExpectations: Dictionary mapping event IDs to expectations for events from NDB
    ///   - negentropyEventExpectations: Dictionary mapping event IDs to expectations for events from negentropy
    ///   - ndbEoseExpectation: Optional expectation to fulfill when NDB EOSE is received
    ///   - networkEoseExpectation: Optional expectation to fulfill when network EOSE is received
    ///   - eoseExpectation: Optional expectation to fulfill when final EOSE is received
    private func runAdvancedStream(
        networkManager: NostrNetworkManager,
        filters: [NostrFilter],
        streamMode: NostrNetworkManager.StreamMode,
        ndbEventExpectations: [NoteId: XCTestExpectation],
        negentropyEventExpectations: [NoteId: XCTestExpectation],
        ndbEoseExpectation: XCTestExpectation? = nil,
        networkEoseExpectation: XCTestExpectation? = nil,
        eoseExpectation: XCTestExpectation? = nil,
    ) {
        Task {
            var ndbEoseSeen = false
            var seenBeforeNdbEose: Set<NoteId> = []
            var alreadyFulfilled: Set<NoteId> = []
            
            for await item in networkManager.reader.advancedStream(filters: filters, streamMode: streamMode) {
                switch item {
                case .event(let lender):
                    try? lender.borrow { event in
                        // Check if this event came before or after NDB EOSE
                        if !ndbEoseSeen {
                            // Before `ndbEose` NostrDB is the only source there can be: under a
                            // `.negentropy` network optimization `SubscriptionManager` does not start the
                            // network stream at all until the NDB stream has emitted its EOSE
                            // (`SubscriptionManager.advancedStream`, the `.ndbEose` branch). That is a
                            // real guarantee, and the one the DM/giftwrap backfill leans on: the
                            // negentropy vector is built from these events, so reconciliation must not
                            // begin until they have all been seen. An event only the relay holds
                            // appearing here means that guarantee broke.
                            if negentropyEventExpectations[event.id] != nil {
                                XCTFail("Event \(event.id) arrived from NDB (before ndbEose) but was expected from negentropy (after ndbEose). This indicates incorrect streaming behavior.")
                            }
                            
                            seenBeforeNdbEose.insert(event.id)
                            if let expectation = ndbEventExpectations[event.id], alreadyFulfilled.insert(event.id).inserted {
                                expectation.fulfill()
                            }
                        } else {
                            // After `ndbEose` there are *two* sources, not one, so "arrived late" does
                            // not imply "came from negentropy". The NDB subscription stays live past its
                            // EOSE by design — that is what makes it a subscription — and re-emits
                            // whatever is ingested next, including the very notes negentropy just pulled
                            // down; `multiSessionNdbStream` also restarts a finished NDB session and
                            // replays its initial results. So a *repeat* delivery of an event we already
                            // got from NDB is expected behaviour, not a bug.
                            //
                            // What would be a bug is an event NDB already held showing up here for the
                            // *first* time: that means it was missing from the negentropy vector when
                            // reconciliation started, so a relay re-sent something we had — precisely
                            // the waste negentropy exists to avoid. That is what is asserted below.
                            if ndbEventExpectations[event.id] != nil && !seenBeforeNdbEose.contains(event.id) {
                                XCTFail("Event \(event.id) reached the stream for the first time after ndbEose, but NDB already had it before the stream started. The negentropy vector was incomplete when reconciliation began, so a relay re-sent an event we already had.")
                            }
                            
                            if let expectation = negentropyEventExpectations[event.id], alreadyFulfilled.insert(event.id).inserted {
                                expectation.fulfill()
                            }
                        }
                    }
                case .ndbEose:
                    ndbEoseSeen = true
                    ndbEoseExpectation?.fulfill()
                case .networkEose:
                    networkEoseExpectation?.fulfill()
                case .eose:
                    eoseExpectation?.fulfill()
                    return
                }
            }
        }
    }
    
    // MARK: - Test Cases
    
    /// Test basic negentropy streaming where local NDB has one event and relay has two events.
    /// Should stream noteA from NDB first, then sync noteB via negentropy from the relay.
    func testBasicNegentropyStreaming() async throws {
        // Given: A relay with noteA and noteB, and local NDB has noteA
        let relay = try await setupRelay()
        let relayUrl = RelayURL(await relay.url().description)!
        
        let noteA = NostrEvent(content: "A", keypair: test_keypair)!
        let noteB = NostrEvent(content: "B", keypair: test_keypair)!
        
        let relayConnection = await connectToRelay(url: relayUrl)
        sendEvents([noteA, noteB], to: relayConnection)
        
        let ndb = await test_damus_state.ndb
        try await storeEventsInNdb([noteA], ndb: ndb)
        
        let networkManager = try await setupNetworkManager(with: [relayUrl], ndb: ndb)
        
        let getsNoteAFromNdb = XCTestExpectation(description: "Gets note A from NDB before ndbEose")
        let getsNoteBFromNegentropy = XCTestExpectation(description: "Gets note B via negentropy after ndbEose")
        let ndbEose = XCTestExpectation(description: "Receives NDB EOSE")
        let networkEose = XCTestExpectation(description: "Receives network EOSE")
        
        // When: Using negentropy streaming mode
        runAdvancedStream(
            networkManager: networkManager,
            filters: [NostrFilter(kinds: [.text])],
            streamMode: .ndbAndNetworkParallel(networkOptimization: .negentropy(liveStreamSinceBackoff: 0)),
            ndbEventExpectations: [noteA.id: getsNoteAFromNdb],
            negentropyEventExpectations: [noteB.id: getsNoteBFromNegentropy],
            ndbEoseExpectation: ndbEose,
            networkEoseExpectation: networkEose
        )
        
        // Then: Should receive noteA from NDB, then ndbEose, then noteB via negentropy, then networkEose
        await fulfillment(of: [getsNoteAFromNdb, ndbEose, getsNoteBFromNegentropy, networkEose], timeout: 10.0, enforceOrder: true)
    }
    
    /// Test negentropy streaming with empty local storage.
    /// Should sync all events from the relay via negentropy.
    func testEmptyLocalStorageNegentropySync() async throws {
        // Given: A relay with noteA and noteB, and empty local NDB
        let relay = try await setupRelay()
        let relayUrl = RelayURL(await relay.url().description)!
        
        let noteA = NostrEvent(content: "A", keypair: test_keypair)!
        let noteB = NostrEvent(content: "B", keypair: test_keypair)!
        
        let relayConnection = await connectToRelay(url: relayUrl)
        sendEvents([noteA, noteB], to: relayConnection)
        
        let ndb = await test_damus_state.ndb
        // Note: Not storing any events in NDB - testing empty local storage
        
        let networkManager = try await setupNetworkManager(with: [relayUrl], ndb: ndb)
        
        let getsNoteAFromNegentropy = XCTestExpectation(description: "Gets note A via negentropy after ndbEose")
        let getsNoteBFromNegentropy = XCTestExpectation(description: "Gets note B via negentropy after ndbEose")
        let ndbEose = XCTestExpectation(description: "Receives NDB EOSE")
        let networkEose = XCTestExpectation(description: "Receives network EOSE")
        
        // When: Using negentropy streaming mode with empty local storage
        runAdvancedStream(
            networkManager: networkManager,
            filters: [NostrFilter(kinds: [.text])],
            streamMode: .ndbAndNetworkParallel(networkOptimization: .negentropy(liveStreamSinceBackoff: 0)),
            ndbEventExpectations: [:],
            negentropyEventExpectations: [noteA.id: getsNoteAFromNegentropy, noteB.id: getsNoteBFromNegentropy],
            ndbEoseExpectation: ndbEose,
            networkEoseExpectation: networkEose
        )
        
        // Then: Should receive ndbEose first, then all events via negentropy, then networkEose
        // (Order not enforced because we don't make guarantees on the order of A/B)
        await fulfillment(of: [ndbEose, getsNoteAFromNegentropy, getsNoteBFromNegentropy, networkEose], timeout: 10.0)
    }
    
    /// Test negentropy streaming when all events are already synced locally.
    /// Should stream events from NDB only, without syncing from relays.
    func testAllEventsSyncedNegentropyMode() async throws {
        // Given: A relay with noteA and noteB, and local NDB has both events
        let relay = try await setupRelay()
        let relayUrl = RelayURL(await relay.url().description)!
        
        let noteA = NostrEvent(content: "A", keypair: test_keypair)!
        let noteB = NostrEvent(content: "B", keypair: test_keypair)!
        
        let relayConnection = await connectToRelay(url: relayUrl)
        sendEvents([noteA, noteB], to: relayConnection)
        
        let ndb = await test_damus_state.ndb
        try await storeEventsInNdb([noteA, noteB], ndb: ndb)
        
        let networkManager = try await setupNetworkManager(with: [relayUrl], ndb: ndb)
        
        let getsNoteAFromNdb = XCTestExpectation(description: "Gets note A from NDB before ndbEose")
        let getsNoteBFromNdb = XCTestExpectation(description: "Gets note B from NDB before ndbEose")
        let ndbEose = XCTestExpectation(description: "Receives NDB EOSE")
        let networkEose = XCTestExpectation(description: "Receives network EOSE")
        
        // When: Using negentropy streaming mode with all events already synced
        runAdvancedStream(
            networkManager: networkManager,
            filters: [NostrFilter(kinds: [.text])],
            streamMode: .ndbAndNetworkParallel(networkOptimization: .negentropy(liveStreamSinceBackoff: 0)),
            ndbEventExpectations: [noteA.id: getsNoteAFromNdb, noteB.id: getsNoteBFromNdb],
            negentropyEventExpectations: [:],
            ndbEoseExpectation: ndbEose,
            networkEoseExpectation: networkEose
        )
        
        // Then: Should receive all events from NDB before ndbEose, then networkEose (no new events to sync)
        // (Order not enforced because we don't make guarantees on the order of A/B)
        await fulfillment(of: [getsNoteAFromNdb, getsNoteBFromNdb, ndbEose, networkEose], timeout: 10.0)
    }
    
    /// Test negentropy streaming with two relays having overlapping events.
    /// Relay1 has noteA+noteB, Relay2 has noteB+noteC, local NDB has noteB.
    /// Should stream noteB from NDB, then sync noteA and noteC via negentropy (deduplicating noteB).
    func testTwoRelaysWithOverlapNegentropySync() async throws {
        // Given: Two relays with overlapping events and local NDB has noteB
        let relay1 = try await setupRelay()
        let relay2 = try await setupRelay()
        
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
        
        let ndb = await test_damus_state.ndb
        try await storeEventsInNdb([noteB], ndb: ndb)
        
        let networkManager = try await setupNetworkManager(with: [relayUrl1, relayUrl2], ndb: ndb)
        
        let getsNoteBFromNdb = XCTestExpectation(description: "Gets note B from NDB before ndbEose")
        let getsNoteAFromNegentropy = XCTestExpectation(description: "Gets note A via negentropy after ndbEose")
        let getsNoteCFromNegentropy = XCTestExpectation(description: "Gets note C via negentropy after ndbEose")
        let ndbEose = XCTestExpectation(description: "Receives NDB EOSE")
        let networkEose = XCTestExpectation(description: "Receives network EOSE")
        
        // When: Using negentropy streaming mode across two relays
        runAdvancedStream(
            networkManager: networkManager,
            filters: [NostrFilter(kinds: [.text])],
            streamMode: .ndbAndNetworkParallel(networkOptimization: .negentropy(liveStreamSinceBackoff: 0)),
            ndbEventExpectations: [noteB.id: getsNoteBFromNdb],
            negentropyEventExpectations: [noteA.id: getsNoteAFromNegentropy, noteC.id: getsNoteCFromNegentropy],
            ndbEoseExpectation: ndbEose,
            networkEoseExpectation: networkEose
        )
        
        // Then: Should receive noteB from NDB, then ndbEose, then noteA and noteC via negentropy
        // (Order not enforced because we don't make guarantees on the order of A/C)
        await fulfillment(of: [getsNoteBFromNdb, ndbEose, getsNoteAFromNegentropy, getsNoteCFromNegentropy, networkEose], timeout: 10.0)
    }
    
    /// Test negentropy streaming with three relays having different overlapping patterns.
    /// Relay1 has A+B, Relay2 has B+C, Relay3 has C+D, local NDB has A+C.
    /// Should stream A and C from NDB, then sync B and D via negentropy.
    func testThreeRelaysPartialSyncNegentropy() async throws {
        // Given: Three relays with overlapping events and local NDB has noteA and noteC
        let relay1 = try await setupRelay()
        let relay2 = try await setupRelay()
        let relay3 = try await setupRelay()
        
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
        
        let ndb = await test_damus_state.ndb
        try await storeEventsInNdb([noteA, noteC], ndb: ndb)
        
        let networkManager = try await setupNetworkManager(with: [relayUrl1, relayUrl2, relayUrl3], ndb: ndb)
        
        let getsNoteAFromNdb = XCTestExpectation(description: "Gets note A from NDB before ndbEose")
        let getsNoteCFromNdb = XCTestExpectation(description: "Gets note C from NDB before ndbEose")
        let getsNoteBFromNegentropy = XCTestExpectation(description: "Gets note B via negentropy after ndbEose")
        let getsNoteDFromNegentropy = XCTestExpectation(description: "Gets note D via negentropy after ndbEose")
        let ndbEose = XCTestExpectation(description: "Receives NDB EOSE")
        let networkEose = XCTestExpectation(description: "Receives network EOSE")
        
        // When: Using negentropy streaming mode across three relays with partial overlap
        runAdvancedStream(
            networkManager: networkManager,
            filters: [NostrFilter(kinds: [.text])],
            streamMode: .ndbAndNetworkParallel(networkOptimization: .negentropy(liveStreamSinceBackoff: 0)),
            ndbEventExpectations: [noteA.id: getsNoteAFromNdb, noteC.id: getsNoteCFromNdb],
            negentropyEventExpectations: [noteB.id: getsNoteBFromNegentropy, noteD.id: getsNoteDFromNegentropy],
            ndbEoseExpectation: ndbEose,
            networkEoseExpectation: networkEose
        )
        
        // Then: Should receive A and C from NDB, then ndbEose, then B and D via negentropy
        // (Order not enforced because we don't make guarantees on the order of A/C and B/D)
        await fulfillment(of: [getsNoteAFromNdb, getsNoteCFromNdb, ndbEose, getsNoteBFromNegentropy, getsNoteDFromNegentropy, networkEose], timeout: 10.0)
    }
    
    /// Test negentropy streaming with multiple filters for different event kinds.
    /// Relay1 has text notes A+B (kind 1), Relay2 has text B + DM C (kind 4), Relay3 has DMs C+D (kind 4).
    /// Local NDB has text note A (kind 1) and DM C (kind 4).
    /// Should stream A and C from NDB, then sync B and D via negentropy.
    func testMultipleFiltersWithDifferentKindsNegentropy() async throws {
        // Given: Three relays with mixed event kinds and local NDB has text note A and DM C
        let relay1 = try await setupRelay()
        let relay2 = try await setupRelay()
        let relay3 = try await setupRelay()
        
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
        
        let ndb = await test_damus_state.ndb
        try await storeEventsInNdb([noteA, noteC], ndb: ndb)
        
        let networkManager = try await setupNetworkManager(with: [relayUrl1, relayUrl2, relayUrl3], ndb: ndb)
        
        let getsNoteAFromNdb = XCTestExpectation(description: "Gets text note A from NDB before ndbEose")
        let getsNoteCFromNdb = XCTestExpectation(description: "Gets DM C from NDB before ndbEose")
        let getsNoteBFromNegentropy = XCTestExpectation(description: "Gets text note B via negentropy after ndbEose")
        let getsNoteDFromNegentropy = XCTestExpectation(description: "Gets DM D via negentropy after ndbEose")
        let ndbEose = XCTestExpectation(description: "Receives NDB EOSE")
        let networkEose = XCTestExpectation(description: "Receives network EOSE")
        
        // When: Using negentropy streaming with multiple filters for different kinds
        // Use two filters: one for kind 1 (text), one for kind 4 (DMs)
        runAdvancedStream(
            networkManager: networkManager,
            filters: [
                NostrFilter(kinds: [.text]),           // kind 1
                NostrFilter(kinds: [.dm])              // kind 4
            ],
            streamMode: .ndbAndNetworkParallel(networkOptimization: .negentropy(liveStreamSinceBackoff: 0)),
            ndbEventExpectations: [noteA.id: getsNoteAFromNdb, noteC.id: getsNoteCFromNdb],
            negentropyEventExpectations: [noteB.id: getsNoteBFromNegentropy, noteD.id: getsNoteDFromNegentropy],
            ndbEoseExpectation: ndbEose,
            networkEoseExpectation: networkEose
        )
        
        // Then: Should receive A and C from NDB, then ndbEose, then B and D via negentropy.
        // (Order not enforced because we don't make guarantees on the order of A/C and B/D
        await fulfillment(of: [getsNoteAFromNdb, getsNoteCFromNdb, ndbEose, getsNoteBFromNegentropy, getsNoteDFromNegentropy, networkEose], timeout: 10.0)
    }
    
    func testPartialUnsupportedRelayPool() async throws {
        // Given: Two relays (one with negentropy, another one not), and the one with negentropy has an event we need
        let relay2 = try await setupRelay()
        
        // The relay that cannot reconcile. `RelayBuilder` has no knob for turning NIP-77 off, so this
        // is a hand-rolled stand-in whose NIP-11 document leaves NIP-77 out, and which is otherwise a
        // well-behaved (if empty) NIP-01 relay — see `NegentropyRefusingRelay` at the bottom of this
        // file. It used to be `ws://nos.lol/v2`, which made the outcome depend on the public internet
        // and on whether that relay happened to have negentropy enabled that day.
        let relay1 = try await NegentropyRefusingRelay.started()
        defer { relay1.stop() }
        
        let relayUrl1 = relay1.url
        let relayUrl2 = RelayURL(await relay2.url().description)!
        
        let noteA = NostrEvent(content: "A", keypair: test_keypair)!
        let noteB = NostrEvent(content: "B", keypair: test_keypair)!
        
        // Connect to relay1 and send noteA + noteB
        let relayConnection2 = await connectToRelay(url: relayUrl2, label: "Relay1")
        sendEvents([noteA, noteB], to: relayConnection2)
        
        let ndb = await test_damus_state.ndb
        try await storeEventsInNdb([noteB], ndb: ndb)
        
        let networkManager = try await setupNetworkManager(with: [relayUrl1, relayUrl2], ndb: ndb)
        
        let getsNoteBFromNdb = XCTestExpectation(description: "Gets note B from NDB before ndbEose")
        let getsNoteAFromNegentropy = XCTestExpectation(description: "Gets note A via negentropy after ndbEose")
        let ndbEose = XCTestExpectation(description: "Receives NDB EOSE")
        let networkEose = XCTestExpectation(description: "Receives network EOSE")
        let generalEose = XCTestExpectation(description: "Receives general EOSE")
        
        // When: Using negentropy streaming mode across two relays
        runAdvancedStream(
            networkManager: networkManager,
            filters: [NostrFilter(kinds: [.text])],
            streamMode: .ndbAndNetworkParallel(networkOptimization: .negentropy(liveStreamSinceBackoff: 0)),
            ndbEventExpectations: [noteB.id: getsNoteBFromNdb],
            negentropyEventExpectations: [noteA.id: getsNoteAFromNegentropy],
            ndbEoseExpectation: ndbEose,
            networkEoseExpectation: networkEose,
            eoseExpectation: generalEose
        )
        
        // Then: Should receive noteB from NDB, then ndbEose, then noteA via negentropy
        await fulfillment(of: [getsNoteBFromNdb, ndbEose, getsNoteAFromNegentropy, networkEose, generalEose], timeout: 10.0)
    }
}

// MARK: - Test Doubles

/// A local relay that says it does not support NIP-77, and speaks just enough of NIP-01 and of the
/// WebSocket protocol to be a well-behaved (if empty) member of a `RelayPool`.
///
/// It exists because `RelayBuilder` — and so `LocalRelay` — has no way to turn negentropy support
/// off, while the behaviour worth testing here is a pool where only *some* relays can reconcile.
/// The test used to reach for `ws://nos.lol/v2` instead, which made the outcome depend on the public
/// internet and on whichever NIPs that operator had enabled that day.
///
/// It is hand-rolled on a raw TCP listener rather than on `NWProtocolWebSocket` because the relay has
/// to answer **two** protocols on one port. Before reconciling, `RelayConnection.getMissingIds`
/// fetches the relay's NIP-11 document over plain HTTP; a WebSocket-only listener leaves that request
/// hanging until `URLSession` gives up a minute later, which is long past any test's patience. Here
/// the HTTP GET is answered with a document listing NIP-1 and not NIP-77, which is the relay saying
/// in the ordinary way that it cannot reconcile — and is what makes this fast and deterministic.
///
/// The rest is deliberately minimal:
/// - `REQ` → an immediate `EOSE`. It stores nothing, so it has nothing to return, and answering at
///   once keeps `RelayPool.subscribe`'s EOSE bookkeeping honest instead of leaving it to the
///   5-second fallback timer.
/// - `NEG-OPEN` → `NEG-ERR`, for the belt-and-braces case where something asks to reconcile anyway.
/// - everything else (`CLOSE`, `NEG-CLOSE`, `EVENT`, …) → ignored.
/// - WebSocket frames are read one per message; fragmented frames are not reassembled, which no
///   Nostr client sends for messages this small.
private final class NegentropyRefusingRelay: @unchecked Sendable {
    private let listener: NWListener
    private let queue: DispatchQueue
    private var peers: [Peer] = []

    /// The `ws://` URL this relay is reachable at.
    let url: RelayURL

    /// The NIP-11 document handed to anyone who asks over HTTP. NIP-77 is pointedly absent.
    private static let relayInformationDocument = """
    {"name":"NegentropyRefusingRelay","description":"Test double: NIP-01 only, no negentropy","supported_nips":[1],"software":"damusTests","version":"1"}
    """

    /// Starts a relay on an ephemeral loopback port.
    ///
    /// The port is `.any` rather than a fixed number so that parallel test destinations sharing the
    /// host's loopback cannot collide on it.
    static func started() async throws -> NegentropyRefusingRelay {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let listener = try NWListener(using: parameters, on: .any)
        let queue = DispatchQueue(label: "NegentropyRefusingRelay")
        // Nothing can reach us before `started()` returns and hands out the URL, so anything that
        // arrives in the gap between `start` and the real handler below is not ours to serve.
        listener.newConnectionHandler = { $0.cancel() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            // `stateUpdateHandler` keeps firing after the listener is up, and a continuation may only
            // be resumed once.
            let resume = ResumeOnce()
            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if resume.claim() { continuation.resume() }
                case .failed(let error):
                    if resume.claim() { continuation.resume(throwing: error) }
                case .cancelled:
                    if resume.claim() { continuation.resume(throwing: CancellationError()) }
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }

        guard let port = listener.port?.rawValue, let url = RelayURL("ws://127.0.0.1:\(port)") else {
            listener.cancel()
            throw StartupError.couldNotDetermineURL
        }

        let relay = NegentropyRefusingRelay(listener: listener, queue: queue, url: url)
        listener.newConnectionHandler = { [weak relay] connection in relay?.accept(connection) }
        return relay
    }

    private init(listener: NWListener, queue: DispatchQueue, url: RelayURL) {
        self.listener = listener
        self.queue = queue
        self.url = url
    }

    func stop() {
        listener.cancel()
        queue.async {
            for peer in self.peers { peer.connection.cancel() }
            self.peers = []
        }
    }

    // MARK: Connection handling

    /// One connected client, and whatever of its bytes we have not made a message out of yet.
    private final class Peer {
        let connection: NWConnection
        var inbox: [UInt8] = []
        var upgraded = false

        init(connection: NWConnection) {
            self.connection = connection
        }
    }

    private func accept(_ connection: NWConnection) {
        let peer = Peer(connection: connection)
        queue.async { self.peers.append(peer) }
        connection.start(queue: queue)
        read(peer)
    }

    private func read(_ peer: Peer) {
        peer.connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                peer.inbox.append(contentsOf: data)
                self.process(peer)
            }
            guard !isComplete, error == nil else {
                peer.connection.cancel()
                return
            }
            self.read(peer)
        }
    }

    private func process(_ peer: Peer) {
        if !peer.upgraded {
            guard let headerEnd = indexAfterHTTPHeaders(in: peer.inbox) else { return }
            let head = String(decoding: peer.inbox[..<headerEnd], as: UTF8.self)
            peer.inbox.removeFirst(headerEnd)
            guard let key = webSocketKey(inHeaders: head) else {
                // Not a WebSocket upgrade, so it is the NIP-11 fetch. Answer it and hang up.
                send(bytes: Array(httpRelayInformationResponse().utf8), on: peer, thenClose: true)
                return
            }
            send(bytes: Array(webSocketHandshakeResponse(forKey: key).utf8), on: peer, thenClose: false)
            peer.upgraded = true
        }

        while let frame = nextFrame(from: &peer.inbox) {
            switch frame.opcode {
            case 0x1:   // text
                handle(message: String(decoding: frame.payload, as: UTF8.self), on: peer)
            case 0x8:   // close
                peer.connection.cancel()
                return
            case 0x9:   // ping
                send(frame: 0xA, payload: frame.payload, on: peer, thenClose: false)
            default:
                break
            }
        }
    }

    private func handle(message: String, on peer: Peer) {
        guard let data = message.data(using: .utf8),
              let array = try? JSONSerialization.jsonObject(with: data) as? [Any],
              array.count >= 2,
              let verb = array[0] as? String,
              let subscriptionId = array[1] as? String
        else { return }

        switch verb {
        case "REQ":
            send(json: ["EOSE", subscriptionId], on: peer)
        case "NEG-OPEN":
            send(json: ["NEG-ERR", subscriptionId, "blocked: negentropy is not supported by this relay"], on: peer)
        default:
            break
        }
    }

    // MARK: HTTP

    /// The offset just past the blank line that ends an HTTP header block, or `nil` if it has not all
    /// arrived yet.
    private func indexAfterHTTPHeaders(in bytes: [UInt8]) -> Int? {
        let terminator: [UInt8] = Array("\r\n\r\n".utf8)
        guard bytes.count >= terminator.count else { return nil }
        for start in 0...(bytes.count - terminator.count) where Array(bytes[start..<start + terminator.count]) == terminator {
            return start + terminator.count
        }
        return nil
    }

    private func webSocketKey(inHeaders headers: String) -> String? {
        for line in headers.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].lowercased() == "sec-websocket-key" else { continue }
            return parts[1].trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private func httpRelayInformationResponse() -> String {
        let body = Self.relayInformationDocument
        return """
        HTTP/1.1 200 OK\r
        Content-Type: application/nostr+json\r
        Access-Control-Allow-Origin: *\r
        Content-Length: \(body.utf8.count)\r
        Connection: close\r
        \r
        \(body)
        """
    }

    private func webSocketHandshakeResponse(forKey key: String) -> String {
        // RFC 6455's fixed GUID, concatenated with the client's key and SHA-1'd.
        let magic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let accept = Data(Insecure.SHA1.hash(data: Data((key + magic).utf8))).base64EncodedString()
        return """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: Upgrade\r
        Sec-WebSocket-Accept: \(accept)\r
        \r

        """
    }

    // MARK: WebSocket framing

    private struct Frame {
        let opcode: UInt8
        let payload: [UInt8]
    }

    /// Pulls one complete frame off the front of `bytes`, or returns `nil` and leaves `bytes` alone
    /// when the frame has not fully arrived.
    private func nextFrame(from bytes: inout [UInt8]) -> Frame? {
        guard bytes.count >= 2 else { return nil }
        let opcode = bytes[0] & 0x0F
        let isMasked = bytes[1] & 0x80 != 0
        var length = Int(bytes[1] & 0x7F)
        var offset = 2

        if length == 126 {
            guard bytes.count >= offset + 2 else { return nil }
            length = Int(bytes[offset]) << 8 | Int(bytes[offset + 1])
            offset += 2
        } else if length == 127 {
            guard bytes.count >= offset + 8 else { return nil }
            length = bytes[offset..<offset + 8].reduce(0) { $0 << 8 | Int($1) }
            offset += 8
        }

        var mask: [UInt8] = []
        if isMasked {
            guard bytes.count >= offset + 4 else { return nil }
            mask = Array(bytes[offset..<offset + 4])
            offset += 4
        }

        guard bytes.count >= offset + length else { return nil }
        var payload = Array(bytes[offset..<offset + length])
        if isMasked {
            for index in payload.indices { payload[index] ^= mask[index % 4] }
        }
        bytes.removeFirst(offset + length)
        return Frame(opcode: opcode, payload: payload)
    }

    private func send(json message: [String], on peer: Peer) {
        guard let data = try? JSONSerialization.data(withJSONObject: message) else { return }
        send(frame: 0x1, payload: Array(data), on: peer, thenClose: false)
    }

    private func send(frame opcode: UInt8, payload: [UInt8], on peer: Peer, thenClose: Bool) {
        var bytes: [UInt8] = [0x80 | opcode]      // FIN set: every frame we send is a whole message
        if payload.count < 126 {
            bytes.append(UInt8(payload.count))
        } else if payload.count <= 0xFFFF {
            bytes.append(126)
            bytes.append(UInt8(payload.count >> 8))
            bytes.append(UInt8(payload.count & 0xFF))
        } else {
            bytes.append(127)
            for shift in stride(from: 56, through: 0, by: -8) {
                bytes.append(UInt8((payload.count >> shift) & 0xFF))
            }
        }
        bytes.append(contentsOf: payload)
        send(bytes: bytes, on: peer, thenClose: thenClose)
    }

    private func send(bytes: [UInt8], on peer: Peer, thenClose: Bool) {
        peer.connection.send(content: Data(bytes), completion: .contentProcessed({ _ in
            if thenClose { peer.connection.cancel() }
        }))
    }

    /// Lets exactly one caller through, so a continuation is resumed once no matter how many times
    /// the listener reports its state.
    private final class ResumeOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var used = false

        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if used { return false }
            used = true
            return true
        }
    }

    enum StartupError: Error {
        case couldNotDetermineURL
    }
}


/// Test delegate for NostrNetworkManager that provides minimal configuration for testing
private final class TestNetworkDelegate: NostrNetworkManager.Delegate {
    var ndb: Ndb
    var keypair: Keypair
    var latestContactListEvent: NostrEvent?
    var bootstrapRelays: [RelayURL]
    var developerMode: Bool = false
    var experimentalLocalRelayModelSupport: Bool = false
    var relayModelCache: RelayModelCache
    var relayFilters: RelayFilters
    var nwcWallet: WalletConnectURL?
    
    init(ndb: Ndb, keypair: Keypair, bootstrapRelays: [RelayURL]) {
        self.ndb = ndb
        self.keypair = keypair
        self.bootstrapRelays = bootstrapRelays
        self.relayModelCache = RelayModelCache()
        self.relayFilters = RelayFilters(our_pubkey: keypair.pubkey)
    }
}
