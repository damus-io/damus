//
//  SubscriptionManagerNegentropyTests.swift
//  damus
//
//  Created by Daniel D'Aquino on 2026-01-17.
//

import XCTest
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
    
    /// Stores events in NostrDB for testing purposes.
    /// - Parameters:
    ///   - events: Array of NostrEvent to store in NDB
    ///   - ndb: The Ndb instance to store events in
    private func storeEventsInNdb(_ events: [NostrEvent], ndb: Ndb) {
        for event in events {
            do {
                try ndb.add(event: event)
            } catch {
                XCTFail("Failed to store event in NDB: \(error)")
            }
        }
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
        eoseExpectation: XCTestExpectation? = nil
    ) {
        Task {
            var ndbEoseSeen = false
            
            for await item in networkManager.reader.advancedStream(filters: filters, streamMode: streamMode) {
                switch item {
                case .event(let lender):
                    try? lender.borrow { event in
                        // Check if this event came before or after NDB EOSE
                        if !ndbEoseSeen {
                            // Event came from NDB - verify it's expected from NDB
                            if negentropyEventExpectations[event.id] != nil {
                                XCTFail("Event \(event.id) arrived from NDB (before ndbEose) but was expected from negentropy (after ndbEose). This indicates incorrect streaming behavior.")
                            }
                            
                            if let expectation = ndbEventExpectations[event.id] {
                                expectation.fulfill()
                            }
                        } else {
                            // Event came from negentropy sync (after NDB EOSE) - verify it's expected from negentropy
                            if ndbEventExpectations[event.id] != nil {
                                XCTFail("Event \(event.id) arrived from negentropy (after ndbEose) but was expected from NDB (before ndbEose). This indicates incorrect streaming behavior.")
                            }
                            
                            if let expectation = negentropyEventExpectations[event.id] {
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
        let relay = try await setupRelay(port: 9080)
        let relayUrl = RelayURL(await relay.url().description)!
        
        let noteA = NostrEvent(content: "A", keypair: test_keypair)!
        let noteB = NostrEvent(content: "B", keypair: test_keypair)!
        
        let relayConnection = await connectToRelay(url: relayUrl)
        sendEvents([noteA, noteB], to: relayConnection)
        
        let ndb = await test_damus_state.ndb
        storeEventsInNdb([noteA], ndb: ndb)
        
        let networkManager = try await setupNetworkManager(with: [relayUrl], ndb: ndb)
        
        let getsNoteAFromNdb = XCTestExpectation(description: "Gets note A from NDB before ndbEose")
        let getsNoteBFromNegentropy = XCTestExpectation(description: "Gets note B via negentropy after ndbEose")
        let ndbEose = XCTestExpectation(description: "Receives NDB EOSE")
        let networkEose = XCTestExpectation(description: "Receives network EOSE")
        
        // When: Using negentropy streaming mode
        runAdvancedStream(
            networkManager: networkManager,
            filters: [NostrFilter(kinds: [.text])],
            streamMode: .ndbAndNetworkParallel(networkOptimization: .negentropy),
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
        let relay = try await setupRelay(port: 9081)
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
            streamMode: .ndbAndNetworkParallel(networkOptimization: .negentropy),
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
        let relay = try await setupRelay(port: 9082)
        let relayUrl = RelayURL(await relay.url().description)!
        
        let noteA = NostrEvent(content: "A", keypair: test_keypair)!
        let noteB = NostrEvent(content: "B", keypair: test_keypair)!
        
        let relayConnection = await connectToRelay(url: relayUrl)
        sendEvents([noteA, noteB], to: relayConnection)
        
        let ndb = await test_damus_state.ndb
        storeEventsInNdb([noteA, noteB], ndb: ndb)
        
        let networkManager = try await setupNetworkManager(with: [relayUrl], ndb: ndb)
        
        let getsNoteAFromNdb = XCTestExpectation(description: "Gets note A from NDB before ndbEose")
        let getsNoteBFromNdb = XCTestExpectation(description: "Gets note B from NDB before ndbEose")
        let ndbEose = XCTestExpectation(description: "Receives NDB EOSE")
        let networkEose = XCTestExpectation(description: "Receives network EOSE")
        
        // When: Using negentropy streaming mode with all events already synced
        runAdvancedStream(
            networkManager: networkManager,
            filters: [NostrFilter(kinds: [.text])],
            streamMode: .ndbAndNetworkParallel(networkOptimization: .negentropy),
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
        let relay1 = try await setupRelay(port: 9083)
        let relay2 = try await setupRelay(port: 9084)
        
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
        storeEventsInNdb([noteB], ndb: ndb)
        
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
            streamMode: .ndbAndNetworkParallel(networkOptimization: .negentropy),
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
        let relay1 = try await setupRelay(port: 9085)
        let relay2 = try await setupRelay(port: 9086)
        let relay3 = try await setupRelay(port: 9087)
        
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
        storeEventsInNdb([noteA, noteC], ndb: ndb)
        
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
            streamMode: .ndbAndNetworkParallel(networkOptimization: .negentropy),
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
        let relay1 = try await setupRelay(port: 9089)
        let relay2 = try await setupRelay(port: 9090)
        let relay3 = try await setupRelay(port: 9091)
        
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
        storeEventsInNdb([noteA, noteC], ndb: ndb)
        
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
            streamMode: .ndbAndNetworkParallel(networkOptimization: .negentropy),
            ndbEventExpectations: [noteA.id: getsNoteAFromNdb, noteC.id: getsNoteCFromNdb],
            negentropyEventExpectations: [noteB.id: getsNoteBFromNegentropy, noteD.id: getsNoteDFromNegentropy],
            ndbEoseExpectation: ndbEose,
            networkEoseExpectation: networkEose
        )
        
        // Then: Should receive A and C from NDB, then ndbEose, then B and D via negentropy.
        // (Order not enforced because we don't make guarantees on the order of A/C and B/D
        await fulfillment(of: [getsNoteAFromNdb, getsNoteCFromNdb, ndbEose, getsNoteBFromNegentropy, getsNoteDFromNegentropy, networkEose], timeout: 10.0)
    }
}

// MARK: - Test Doubles

/// Test delegate for NostrNetworkManager that provides minimal configuration for testing
private final class TestNetworkDelegate: NostrNetworkManager.Delegate {
    var ndb: Ndb
    var keypair: Keypair
    var latestRelayListEventIdHex: String?
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
