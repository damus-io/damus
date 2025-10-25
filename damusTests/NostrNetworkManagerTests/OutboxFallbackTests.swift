//
//  OutboxFallbackTests.swift
//  damusTests
//
//  Created by OpenAI Codex on 2025-09-06.
//

import XCTest
@testable import damus

final class OutboxFallbackTests: XCTestCase {
    func testFetchFirstEventFromOutboxReturnsMissingNote() async throws {
        let ndb = Ndb.test
        let fallbackRelay = RelayURL("wss://obscure-relay.example")!
        
        // Prepare relay pool with a stub relay so subscriptions can bind to it
        let relayPool = RelayPool(ndb: ndb)
        try await relayPool.add_relay(.init(url: fallbackRelay, info: .read, variant: .ephemeral))
        await relayPool.markOpenForTesting()
        
        // Store a relay list for the author so the hint provider can discover the fallback relay
        let authorKeypair = test_keypair_full
        ingestRelayList(for: authorKeypair.pubkey, relays: [fallbackRelay], ndb: ndb)
        
        let hints = OutboxRelayHints(ndb: ndb)
        let outbox = OutboxManager(relayPool: relayPool, hints: hints)
        let subscriptionManager = NostrNetworkManager.SubscriptionManager(
            pool: relayPool,
            ndb: ndb,
            experimentalLocalRelayModelSupport: false,
            outboxManager: outbox
        )
        
        // Build a note that only the obscure relay will deliver
        guard let missingNote = NostrEvent(
            content: "fiatjaf hides notes on obscure relays",
            keypair: authorKeypair.to_keypair(),
            kind: NostrKind.text.rawValue
        ) else {
            XCTFail("Failed to build test note")
            return
        }
        let filter = NostrFilter(ids: [missingNote.id], limit: 1)
        let subscriptionId = UUID()
        
        let fetched = Task {
            await subscriptionManager.fetchFirstEventFromOutbox(
                filters: [filter],
                timeout: .seconds(2),
                requestedRelays: nil,
                subscriptionId: subscriptionId
            )
        }
        
        // Give the subscription a brief moment to register before delivering the fake network event
        try await Task.sleep(nanoseconds: 50_000_000)
        await relayPool.handle_event(
            relay_id: fallbackRelay,
            event: .nostr_event(.event(subscriptionId.uuidString, missingNote))
        )
        
        let lender = await fetched.value
        XCTAssertNotNil(lender, "Outbox fallback should return the missing note")
        
        let resolved = try lender?.borrow({ $0.id })
        XCTAssertEqual(resolved, missingNote.id)
    }
}

private extension OutboxFallbackTests {
    func ingestRelayList(for author: Pubkey, relays: [RelayURL], ndb: Ndb) {
        let items = relays.map { NIP65.RelayList.RelayItem(url: $0, rwConfiguration: .read) }
        let relayListEvent = NIP65.RelayList(relays: items)
        guard let signed = relayListEvent.toNostrEvent(keypair: test_keypair_full) else {
            XCTFail("Unable to build relay list")
            return
        }
        guard let encoded = encode_json(signed) else {
            XCTFail("Unable to encode relay list")
            return
        }
        XCTAssertTrue(ndb.process_client_event("[\"EVENT\",\(encoded)]"))
    }
}
