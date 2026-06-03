//
//  RelayPoolTests.swift
//  damusTests
//
//  Created by kernelkind on 12/16/23.
//

import Foundation

import XCTest
@testable import damus

final class RelayPoolTests: XCTestCase {
    
    override func setUpWithError() throws {
    }

    override func tearDownWithError() throws {
    }
    
    @MainActor
    func testAddRelay_ValidRelayURL_NoErrors() async {
        await testAddRelays(urls: [
            "wss://relay.damus.io"
        ])
    }

    @MainActor
    func testAddRelay_TwoSameURLs_ThrowsRelayAlreadyExists() async {
        await testAddRelays(urls: [
            "wss://relay.damus.io",
            "wss://relay.damus.io"
        ], expectedError: .RelayAlreadyExists)
    }

    @MainActor
    func testAddRelay_OneExtraneousSlashURL_ThrowsRelayAlreadyExists() async {
        await testAddRelays(urls: [
            "wss://relay.damus.io",
            "wss://relay.damus.io/"
        ], expectedError: .RelayAlreadyExists)
    }

    @MainActor
    func testAddRelay_MultipleExtraneousSlashURL_ThrowsRelayAlreadyExists() async {
        await testAddRelays(urls: [
            "wss://relay.damus.io",
            "wss://relay.damus.io///"
        ], expectedError: .RelayAlreadyExists)
    }

    @MainActor
    func testAddRelay_ExtraSlashURLFirst_ThrowsRelayAlreadyExists() async {
        await testAddRelays(urls: [
            "wss://relay.damus.io///",
            "wss://relay.damus.io"
        ], expectedError: .RelayAlreadyExists)
    }

    /// Creates fresh inputs for seen-recording tests.
    func makeRecordSeenFixture() throws -> (pool: RelayPool, relay: RelayURL, noteID: NoteId) {
        let relay = try XCTUnwrap(RelayURL("wss://relay.example.com"))
        let noteID = try XCTUnwrap(NoteId(hex: String(repeating: "a", count: 64)))
        return (RelayPool(ndb: nil), relay, noteID)
    }

    /// Verifies successful relay OK responses update the relay provenance map.
    func testRecordSeenRecordsSuccessfulOKResponses() async throws {
        let (pool, relay, noteID) = try makeRecordSeenFixture()
        let result = CommandResult(event_id: noteID, ok: true, msg: "")

        await pool.record_seen(relay_id: relay, event: .nostr_event(.ok(result)))

        let seenRelays = await pool.seen[noteID]
        let relayCount = await pool.counts[relay]

        XCTAssertEqual(seenRelays, Set([relay]))
        XCTAssertEqual(relayCount, Optional(UInt64(1)))
    }

    /// Verifies duplicate relay OK responses do not increment provenance twice.
    func testRecordSeenRecordsDuplicateSuccessfulOKResponsesOnce() async throws {
        let (pool, relay, noteID) = try makeRecordSeenFixture()
        let acceptedResult = CommandResult(event_id: noteID, ok: true, msg: "")
        let duplicateResult = CommandResult(
            event_id: noteID,
            ok: true,
            msg: "duplicate: already have this event"
        )

        await pool.record_seen(relay_id: relay, event: .nostr_event(.ok(acceptedResult)))
        await pool.record_seen(relay_id: relay, event: .nostr_event(.ok(duplicateResult)))

        let seenRelays = await pool.seen[noteID]
        let relayCount = await pool.counts[relay]

        XCTAssertEqual(seenRelays, Set([relay]))
        XCTAssertEqual(relayCount, Optional(UInt64(1)))
    }

    /// Verifies failed relay OK responses do not count as relay provenance.
    func testRecordSeenIgnoresFailedOKResponses() async throws {
        let (pool, relay, noteID) = try makeRecordSeenFixture()
        let result = CommandResult(event_id: noteID, ok: false, msg: "blocked: test")

        await pool.record_seen(relay_id: relay, event: .nostr_event(.ok(result)))

        let seenRelays = await pool.seen[noteID]
        let relayCount = await pool.counts[relay]

        XCTAssertNil(seenRelays)
        XCTAssertNil(relayCount)
    }
}

/// Adds relay URLs to a pool and verifies duplicate URL handling.
@MainActor
func testAddRelays(urls: [String], expectedError: RelayPool.RelayError? = nil) async {
    let relayPool = RelayPool(ndb: nil)

    do {
        for relay in urls {
            guard let url = RelayURL(relay) else {
                XCTFail("Invalid URL encountered: \(relay)")
                return
            }

            let descriptor = RelayPool.RelayDescriptor(url: url, info: .readWrite)
            try await relayPool.add_relay(descriptor)
        }

        if expectedError != nil {
            XCTFail("Expected \(expectedError!) error, but no error was thrown.")
        }
    } catch let error as RelayPool.RelayError where expectedError == .RelayAlreadyExists {
        XCTAssertEqual(error, expectedError!, "Expected RelayAlreadyExists error, got \(error)")
    } catch {
        XCTFail("An unexpected error was thrown: \(error)")
    }
}
