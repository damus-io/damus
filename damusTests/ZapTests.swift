//
//  ZapTests.swift
//  damusTests
//
//  Created by William Casarin on 2023-01-16.
//

import XCTest
@testable import damus

final class ZapTests: XCTestCase {

    override func setUpWithError() throws {
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func test_alby_zap() throws {
        let zapjson = "eyJjb250ZW50Ijoi4pqhTm9uLWN1c3RvZGlhbCB6YXAgZnJvbSBteSBBbGJ5IEh1YiIsImNyZWF0ZWRfYXQiOjE3MjQ2ODUwNDcsImlkIjoiNGM3NWFiMWU3MDk4Y2NiN2FlYjhmZjdkNDIwMjM2ZDM1N2U1OGNjZmI3OWZiZTEwMTcwNGNiMzY0OTg3YjY4YSIsImtpbmQiOjk3MzUsInB1YmtleSI6Ijc5ZjAwZDNmNWExOWVjODA2MTg5ZmNhYjAzYzFiZTRmZjgxZDE4ZWU0ZjY1M2M4OGZhYzQxZmUwMzU3MGY0MzIiLCJzaWciOiI3OWM5ZDJjN2ExZWI1NmNhZjMyOTY1ZTRkMDJlYjJiYjFmYTY3NGViMDM4ZWE2MmFjZTg2YzBiMzA2OTJhMjU0YWU0M2JhNmMzNjcyMDJkZjgxNzQ5NGNhNTg4NzRkNWI1OWMxY2VhMDdjZTk5Mjk0MmIyOWYwZmVlZmJlM2FiZCIsInRhZ3MiOltbInAiLCIxNWI1Y2Y2Y2RmNGZkMWMwMmYyOGJjY2UwZjE5N2NhZmFlNGM4YzdjNjZhM2UyZTIzYWY5ZmU2MTA4NzUzMTVlIl0sWyJlIiwiYmNiMmZjZmUxYzQ2N2M1ZWM4Mjg1ZTM4NWMzNmVjMTM4Nzk3MDljZWQ5ZDg4MDBjYjM0MGViZjIxOGMzMjEwZCJdLFsiUCIsIjA1MjFkYjk1MzEwOTZkZmY3MDBkY2Y0MTBiMDFkYjQ3YWI2NTk4ZGU3ZTVlZjJjNWEyYmQ3ZTExNjAzMTViZjYiXSxbImJvbHQxMSIsImxuYmMxMHUxcG52ZXhoM2RwdXUyZDJ6bm4wZGNra3hhdG53M2hrZzZ0cGRzczg1Y3RzeXBuOHltbWR5cGtoamd6cGQzMzhqZ3pndzQzcW5wNHEyMjhhMnp0eGt3emF5cHZ6cnNoODIzcW5nbXY5N2YydjlwdXd2dHNhZGV0eXBtdXR5c2N3cHA1dmxjbGwwMHpwcGhoMzJ3OHV0NWpwcDVhMmZtcWg4c3o3bnUyaDd2MDdyMHU1bHN3ZzVsc3NwNXh2YXFlZnpsY2t6bXYwdzg5bHIwazB5dnI1eGQybmc1MmE1cmNkYXJmbTRmMGEwd2dwdXE5cXl5c2dxY3FwY3hxeXo1dnFlcHMzOXNleDUyc2ZtdHU5Z25tNWRhcGs1bGdsZDRwcDk2dXI1YTRhbTk0MHEyNXd6ZHNycmo1MjN4eWEwcnV4YTVscjk2M2cwMjk2cjZtZGZ5MjR2NjUzZXZjcHh5cjBtbWhnd21zcXh2cmhmZCJdLFsicHJlaW1hZ2UiLCJhZDA0N2MwMmZlNWYwNTljODA4NzdkNzk0YmU4OGU0N2M2NDRlYmVkZmRmZTY2M2IyODljOTMxNmRiNDk1ZjJkIl0sWyJkZXNjcmlwdGlvbiIsIntcImtpbmRcIjo5NzM0LFwiY3JlYXRlZF9hdFwiOjE3MjQ2ODUwMzgsXCJjb250ZW50XCI6XCLimqFOb24tY3VzdG9kaWFsIHphcCBmcm9tIG15IEFsYnkgSHViXCIsXCJ0YWdzXCI6W1tcInBcIixcIjE1YjVjZjZjZGY0ZmQxYzAyZjI4YmNjZTBmMTk3Y2FmYWU0YzhjN2M2NmEzZTJlMjNhZjlmZTYxMDg3NTMxNWVcIl0sW1wicmVsYXlzXCIsXCJ3c3M6Ly9wdXJwbGVwYWcuZXMvXCIsXCJ3c3M6Ly9yZWxheS5nZXRhbGJ5LmNvbS92MVwiLFwid3NzOi8vbm9zdHIubW9tL1wiLFwid3NzOi8vbm9zdHIub3h0ci5kZXYvXCIsXCJ3c3M6Ly9ub3MubG9sL1wiLFwid3NzOi8vbm9zdHIud2luZS9cIixcIndzczovL3JlbGF5LmRhbXVzLmlvL1wiLFwid3NzOi8vcmVsYXkubm90b3NoaS53aW4vXCIsXCJ3c3M6Ly9lZGVuLm5vc3RyLmxhbmQvXCJdLFtcImFtb3VudFwiLFwiMTAwMDAwMFwiXSxbXCJlXCIsXCJiY2IyZmNmZTFjNDY3YzVlYzgyODVlMzg1YzM2ZWMxMzg3OTcwOWNlZDlkODgwMGNiMzQwZWJmMjE4YzMyMTBkXCJdXSxcInB1YmtleVwiOlwiMDUyMWRiOTUzMTA5NmRmZjcwMGRjZjQxMGIwMWRiNDdhYjY1OThkZTdlNWVmMmM1YTJiZDdlMTE2MDMxNWJmNlwiLFwiaWRcIjpcIjU3ZDg2MTIwMDc1MjFjMGI1MzJiOTFhZjI0OTgwOTVhMjUxZTYzZjQyNTE4N2U2Yzk1NzAwZmQwYTZiYWI3ZDRcIixcInNpZ1wiOlwiNzk4ZDczNTExOGJjZDE0MjI4YTEyYjZkNTI0MjNmZjI1YmI0ZWQ4Y2Q1ZGFjZjJmNTk3MWVmNTczZmRjM2ZjMDVmYzc5MzE4NWU2OTY4MmNjYTI0M2Q2NGYxNDdhNDQ5ODk2OGEwYmMyODhhZTgzZTc1YzAzZTk5ZjkzNmE2MDNcIn0iXV19Cg=="

        guard let json_data = Data(base64Encoded: zapjson) else {
            XCTAssert(false)
            return
        }

        let json_str = String(decoding: json_data, as: UTF8.self)

        guard let ev = decode_nostr_event_json(json: json_str) else {
            XCTAssert(false)
            return
        }

        let zapper = Pubkey(hex: "79f00d3f5a19ec806189fcab03c1be4ff81d18ee4f653c88fac41fe03570f432")!
        guard let zap = Zap.from_zap_event(zap_ev: ev, zapper: zapper, our_privkey: nil) else {
            XCTAssert(false)
            return
        }

        let note_id = NoteId(hex: "bcb2fcfe1c467c5ec8285e385c36ec13879709ced9d8800cb340ebf218c3210d")!
        let author = Pubkey(hex: "15b5cf6cdf4fd1c02f28bcce0f197cafae4c8c7c66a3e2e23af9fe610875315e")!
        XCTAssertEqual(zap.zapper, zapper)
        XCTAssertEqual(zap.target, ZapTarget.note(id: note_id, author: author))

        XCTAssertEqual(NotificationFormatter.zap_notification_title(zap), "Zap")
        XCTAssertEqual(NotificationFormatter.zap_notification_body(profiles: Profiles(ndb: test_damus_state.ndb), zap: zap), "You received 1k sats from npub1q5sa...ky65: \"⚡Non-custodial zap from my Alby Hub\"")


    }

    func test_private_zap() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let target = ZapTarget.profile(bob.pubkey)
        
        let message = "hey bob!"
        let mzapreq = make_zap_request_event(keypair: alice, content: message, relays: [], target: target, zap_type: .priv)
        
        XCTAssertNotNil(mzapreq)
        guard let mzapreq else {
            return
        }
        
        let zapreq = mzapreq.potentially_anon_outer_request.ev
        let decrypted = decrypt_private_zap(our_privkey: bob.privkey, zapreq: zapreq, target: target)
        
        XCTAssertNotNil(decrypted)
        guard let decrypted else {
            return
        }
        
        XCTAssertEqual(zapreq.content, "")
        XCTAssertEqual(decrypted.pubkey, alice.pubkey)
        XCTAssertEqual(message, decrypted.content)
    }
    
    @MainActor
    func testZap() throws {
        let zapjson = "eyJpZCI6IjUzNmJlZTllODNjODE4ZTNiODJjMTAxOTM1MTI4YWUyN2EwZDQyOTAwMzlhYWYyNTNlZmU1ZjA5MjMyYzE5NjIiLCJwdWJrZXkiOiI5NjMwZjQ2NGNjYTZhNTE0N2FhOGEzNWYwYmNkZDNjZTQ4NTMyNGU3MzJmZDM5ZTA5MjMzYjFkODQ4MjM4ZjMxIiwiY3JlYXRlZF9hdCI6MTY3NDIwNDUzNSwia2luZCI6OTczNSwidGFncyI6W1sicCIsIjMyZTE4Mjc2MzU0NTBlYmIzYzVhN2QxMmMxZjhlN2IyYjUxNDQzOWFjMTBhNjdlZWYzZDlmZDljNWM2OGUyNDUiXSxbImJvbHQxMSIsImxuYmMxMHUxcDN1NTR0bnNwNTcyOXF2eG5renRqamtkNTg1eW4wbDg2MzBzMm01eDZsNTZ3eXk0ZWMybnU4eHV6NjI5eHFwcDV2MnE3aHVjNGpwamgwM2Z4OHVqZXQ1Nms3OWd4cXg3bWUycGV2ejZqMms4dDhtNGxnNXZxaHA1eWc1MDU3OGNtdWoyNG1mdDNxcnNybWd3ZjMwa2U3YXY3ZDc3Z2FtZmxkazlrNHNmMzltcXhxeWp3NXFjcXBqcnpqcTJoeWVoNXEzNmx3eDZ6dHd5cmw2dm1tcnZ6NnJ1ZndqZnI4N3lremZuYXR1a200dWRzNHl6YWszc3FxOW1jcXFxcXFxcWxncXFxcTg2cXF5ZzlxeHBxeXNncWFkeWVjdmR6ZjI3MHBkMzZyc2FmbDA3azQ1ZmNqMnN5OGU1djJ0ZW5kNTB2OTU3NnV4cDNkdmp6amV1aHJlODl5cGdjbTkwZDZsbTAwNGszMHlqNGF2NW1jc3M1bnl4NHU5bmVyOWdwcHY2eXF3Il0sWyJkZXNjcmlwdGlvbiIsIntcImlkXCI6XCJiMDkyMTYzNGIxYmI4ZWUzNTg0YmJiZjJlOGQ3OTBhZDk4NTk5ZDhlMDhmODFjNzAwZGRiZTQ4MjAxNTY4Yjk3XCIsXCJwdWJrZXlcIjpcIjdmYTU2ZjVkNjk2MmFiMWUzY2Q0MjRlNzU4YzMwMDJiODY2NWY3YjBkOGRjZWU5ZmU5ZTI4OGQ3NzUxYWMxOTRcIixcImNyZWF0ZWRfYXRcIjoxNjc0MjA0NTMxLFwia2luZFwiOjk3MzQsXCJ0YWdzXCI6W1tcInBcIixcIjMyZTE4Mjc2MzU0NTBlYmIzYzVhN2QxMmMxZjhlN2IyYjUxNDQzOWFjMTBhNjdlZWYzZDlmZDljNWM2OGUyNDVcIl0sW1wicmVsYXlzXCIsXCJ3c3M6Ly9yZWxheS5zbm9ydC5zb2NpYWxcIixcIndzczovL3JlbGF5LmRhbXVzLmlvXCIsXCJ3c3M6Ly9ub3N0ci1wdWIud2VsbG9yZGVyLm5ldFwiLFwid3NzOi8vbm9zdHIudjBsLmlvXCIsXCJ3c3M6Ly9wcml2YXRlLW5vc3RyLnYwbC5pb1wiLFwid3NzOi8vbm9zdHIuemViZWRlZS5jbG91ZFwiLFwid3NzOi8vcmVsYXkubm9zdHIuaW5mby9cIl1dLFwiY29udGVudFwiOlwiXCIsXCJzaWdcIjpcImQwODQwNGU2MjVmOWM1NjMzYWZhZGQxMWMxMTBiYTg4ZmNkYjRiOWUwOTJiOTg0MGU3NDgyYThkNTM3YjFmYzExODY5MmNmZDEzMWRkODMzNTM2NDc2OWE2NzE3NTRhZDdhYTk3MzEzNjgzYTRhZDdlZmI3NjQ3NmMwNGU1ZjE3XCJ9Il0sWyJwcmVpbWFnZSIsIjNlMDJhM2FmOGM4YmNmMmEzNzUzYzg3ZjMxMTJjNjU2YTIwMTE0ZWUwZTk4ZDgyMTliYzU2ZjVlOGE3MjM1YjMiXV0sImNvbnRlbnQiOiIiLCJzaWciOiIzYWI0NGQwZTIyMjhiYmQ0ZDIzNDFjM2ZhNzQwOTZjZmY2ZjU1Y2ZkYTk5YTVkYWRjY2Y0NWM2NjQ2MzdlMjExNTFiMmY5ZGQwMDQwZjFhMjRlOWY4Njg2NzM4YjE2YmY4MTM0YmRiZTQxYTIxOGM5MTFmN2JiMzFlNTk1NzhkMSJ9Cg=="
        
        guard let json_data = Data(base64Encoded: zapjson) else {
            XCTAssert(false)
            return
        }
        
        let json_str = String(decoding: json_data, as: UTF8.self)
        
        guard let ev = decode_nostr_event_json(json: json_str) else {
            XCTAssert(false)
            return
        }
        
        let zapper = Pubkey(hex: "9630f464cca6a5147aa8a35f0bcdd3ce485324e732fd39e09233b1d848238f31")!
        guard let zap = Zap.from_zap_event(zap_ev: ev, zapper: zapper, our_privkey: nil) else {
            XCTAssert(false)
            return
        }

        let profile = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        XCTAssertEqual(zap.zapper, zapper)
        XCTAssertEqual(zap.target, ZapTarget.profile(profile))

        XCTAssertEqual(NotificationFormatter.zap_notification_title(zap), "Zap")
        XCTAssertEqual(NotificationFormatter.zap_notification_body(profiles: Profiles(ndb: test_damus_state.ndb), zap: zap), "You received 1k sats from npub107jk...ncxg")
    }

    // MARK: - ZappingError tests

    /// Test all ZappingError cases return localized human-readable messages
    func test_zapping_error_human_readable_messages() throws {
        // Test each error case has a non-empty localized message
        let errors: [ZappingError] = [
            .fetching_invoice,
            .bad_lnurl,
            .canceled,
            .send_failed,
            .rate_limited,
            .nwc_timeout
        ]

        for error in errors {
            let message = error.humanReadableMessage()
            XCTAssertFalse(message.isEmpty, "Error \(error) should have a non-empty message")
        }
    }

    /// Test specific error message content for NWC timeout
    func test_nwc_timeout_error_mentions_nwc() throws {
        let error = ZappingError.nwc_timeout
        let message = error.humanReadableMessage()
        // Message should mention NWC so user knows to check their wallet connection
        XCTAssertTrue(
            message.lowercased().contains("nwc") || message.lowercased().contains("wallet"),
            "NWC timeout message should mention NWC or wallet connection"
        )
    }

    /// Test rate limited error message
    func test_rate_limited_error_message() throws {
        let error = ZappingError.rate_limited
        let message = error.humanReadableMessage()
        XCTAssertTrue(
            message.lowercased().contains("rate") || message.lowercased().contains("later"),
            "Rate limited message should indicate rate limiting or retry later"
        )
    }

    // MARK: - ZapInvoiceResult tests

    /// Test ZapInvoiceResult enum cases
    func test_zap_invoice_result_success() throws {
        let invoice = "lnbc100u1p55gjvwpp5test"
        let result = ZapInvoiceResult.success(invoice)

        switch result {
        case .success(let inv):
            XCTAssertEqual(inv, invoice)
        case .rateLimited, .error:
            XCTFail("Expected success case")
        }
    }

    func test_zap_invoice_result_rate_limited() throws {
        let result = ZapInvoiceResult.rateLimited

        switch result {
        case .rateLimited:
            break // Expected
        case .success, .error:
            XCTFail("Expected rateLimited case")
        }
    }

    func test_zap_invoice_result_error() throws {
        let result = ZapInvoiceResult.error

        switch result {
        case .error:
            break // Expected
        case .success, .rateLimited:
            XCTFail("Expected error case")
        }
    }

    // MARK: - ZapInvoiceFetchResult tests

    /// Test ZapInvoiceFetchResult struct
    func test_zap_invoice_fetch_result_with_invoice() throws {
        let invoice = "lnbc100u1p55gjvwpp5test"
        let result = ZapInvoiceFetchResult(invoice: invoice, wasRateLimited: false)

        XCTAssertEqual(result.invoice, invoice)
        XCTAssertFalse(result.wasRateLimited)
    }

    func test_zap_invoice_fetch_result_rate_limited() throws {
        let result = ZapInvoiceFetchResult(invoice: nil, wasRateLimited: true)

        XCTAssertNil(result.invoice)
        XCTAssertTrue(result.wasRateLimited)
    }

    func test_zap_invoice_fetch_result_error() throws {
        let result = ZapInvoiceFetchResult(invoice: nil, wasRateLimited: false)

        XCTAssertNil(result.invoice)
        XCTAssertFalse(result.wasRateLimited)
    }

    // MARK: - Failed Zap Integration Tests

    /// Test: PendingZap can transition from fetching_invoice to failed state
    @MainActor
    func test_pending_zap_state_transitions_to_failed() throws {
        let keypair = generate_new_keypair()

        // Create a mock NWC URL for testing
        guard let nwcUrl = WalletConnectURL(str: "nostr+walletconnect://\(keypair.pubkey.hex())?relay=wss://relay.test&secret=\(keypair.privkey.hex())") else {
            XCTFail("Failed to create test WalletConnectURL")
            return
        }

        let nwcState = NWCPendingZapState(state: .fetching_invoice, url: nwcUrl)

        // Verify initial state
        XCTAssertTrue(nwcState.state == NWCStateType.fetching_invoice)

        // Transition to failed
        let updated = nwcState.update_state(state: .failed)
        XCTAssertTrue(updated, "State should have changed")
        XCTAssertTrue(nwcState.state == NWCStateType.failed)
    }

    /// Test: NWC state transitions through full lifecycle to failure
    @MainActor
    func test_nwc_state_full_lifecycle_to_failure() throws {
        let keypair = generate_new_keypair()

        guard let nwcUrl = WalletConnectURL(str: "nostr+walletconnect://\(keypair.pubkey.hex())?relay=wss://relay.test&secret=\(keypair.privkey.hex())") else {
            XCTFail("Failed to create test WalletConnectURL")
            return
        }

        let nwcState = NWCPendingZapState(state: .fetching_invoice, url: nwcUrl)

        // Create a mock NWC request event
        guard let nwcEvent = NostrEvent(content: "test", keypair: keypair.to_keypair(), kind: 23194) else {
            XCTFail("Failed to create NWC event")
            return
        }

        // Transition: fetching_invoice -> postbox_pending
        XCTAssertTrue(nwcState.update_state(state: .postbox_pending(nwcEvent)))
        if case .postbox_pending(let ev) = nwcState.state {
            XCTAssertEqual(ev.id, nwcEvent.id)
        } else {
            XCTFail("Expected postbox_pending state")
        }

        // Transition: postbox_pending -> failed (simulating NWC error response)
        XCTAssertTrue(nwcState.update_state(state: .failed))
        XCTAssertTrue(nwcState.state == NWCStateType.failed)
    }

    /// Test: NWC state does not update when already in same state
    @MainActor
    func test_nwc_state_no_update_when_same() throws {
        let keypair = generate_new_keypair()

        guard let nwcUrl = WalletConnectURL(str: "nostr+walletconnect://\(keypair.pubkey.hex())?relay=wss://relay.test&secret=\(keypair.privkey.hex())") else {
            XCTFail("Failed to create test WalletConnectURL")
            return
        }

        let nwcState = NWCPendingZapState(state: .failed, url: nwcUrl)

        // Attempting to set same state should return false
        let updated = nwcState.update_state(state: .failed)
        XCTAssertFalse(updated, "Should not update when state is the same")
    }

    /// Test: ZapsDataModel removes pending zap correctly
    @MainActor
    func test_zaps_data_model_removes_pending_zap() throws {
        let target = ZapTarget.note(id: test_note.id, author: test_note.pubkey)

        // Create a pending zap using test data
        let pendingZap = PendingZap(
            amount_msat: 10000,
            target: target,
            request: .normal(test_zap_request),
            type: .pub,
            state: .external(.init(state: .fetching_invoice))
        )

        let zapsModel = ZapsDataModel([.pending(pendingZap)])
        XCTAssertEqual(zapsModel.zaps.count, 1)

        // Remove the pending zap
        let reqid = ZapRequestId(from_pending: pendingZap)
        let removed = zapsModel.remove(reqid: reqid)

        XCTAssertTrue(removed)
        XCTAssertEqual(zapsModel.zaps.count, 0)
    }

    /// Test: Zaps cache properly removes pending zap on failure
    @MainActor
    func test_zaps_cache_removes_pending_on_failure() throws {
        // Use fresh DamusState to avoid shared state issues
        let damus = generate_test_damus_state(mock_profile_info: nil)
        let target = ZapTarget.note(id: test_note.id, author: test_note.pubkey)

        // Create unique zap request using test_keypair so pubkey matches damus.our_pubkey
        // (add_zap only adds to our_zaps if request.pubkey == our_pubkey)
        guard let zapReqEvent = NostrEvent(content: "test zap \(UUID())", keypair: test_keypair, kind: 9734) else {
            XCTFail("Failed to create zap request event")
            return
        }
        let zapRequest = ZapRequest(ev: zapReqEvent)

        // Create and add a pending zap
        let pendingZap = PendingZap(
            amount_msat: 10000,
            target: target,
            request: .normal(zapRequest),
            type: .pub,
            state: .external(.init(state: .fetching_invoice))
        )

        damus.zaps.add_zap(zap: .pending(pendingZap))
        XCTAssertNotNil(damus.zaps.zaps[zapReqEvent.id])

        // Simulate failure by removing the zap
        let reqid = ZapRequestId(from_pending: pendingZap)
        let removedZap = damus.zaps.remove_zap(reqid: reqid.reqid)

        XCTAssertNotNil(removedZap)
        XCTAssertNil(damus.zaps.zaps[zapReqEvent.id])
    }

    /// Test: ExtPendingZapState transitions work correctly
    func test_external_pending_zap_state_transitions() throws {
        let extState = ExtPendingZapState(state: .fetching_invoice)

        XCTAssertTrue(extState.state == ExtPendingZapStateType.fetching_invoice)

        extState.state = .done
        XCTAssertTrue(extState.state == ExtPendingZapStateType.done)
    }

    /// Test: Cancellation during fetching_invoice sets cancel state
    @MainActor
    func test_cancel_during_fetching_invoice() throws {
        let keypair = generate_new_keypair()

        guard let nwcUrl = WalletConnectURL(str: "nostr+walletconnect://\(keypair.pubkey.hex())?relay=wss://relay.test&secret=\(keypair.privkey.hex())") else {
            XCTFail("Failed to create test WalletConnectURL")
            return
        }

        let nwcState = NWCPendingZapState(state: .fetching_invoice, url: nwcUrl)

        // Simulate user cancellation during invoice fetch
        XCTAssertTrue(nwcState.update_state(state: .cancel_fetching_invoice))
        XCTAssertTrue(nwcState.state == NWCStateType.cancel_fetching_invoice)
    }

    /// Test: Zapping.is_paid returns false for failed pending zaps
    @MainActor
    func test_zapping_is_paid_false_for_failed() throws {
        let keypair = generate_new_keypair()
        let target = ZapTarget.profile(keypair.pubkey)

        guard let nwcUrl = WalletConnectURL(str: "nostr+walletconnect://\(keypair.pubkey.hex())?relay=wss://relay.test&secret=\(keypair.privkey.hex())") else {
            XCTFail("Failed to create test WalletConnectURL")
            return
        }

        let nwcState = NWCPendingZapState(state: .failed, url: nwcUrl)
        let pendingZap = PendingZap(
            amount_msat: 10000,
            target: target,
            request: .normal(test_zap_request),
            type: .pub,
            state: .nwc(nwcState)
        )

        let zapping = Zapping.pending(pendingZap)

        // Failed zaps should not be considered paid
        XCTAssertFalse(zapping.is_paid)
        XCTAssertTrue(zapping.is_pending)
    }

    /// Test: Zapping.is_paid returns true for confirmed NWC zaps
    @MainActor
    func test_zapping_is_paid_true_for_confirmed() throws {
        let keypair = generate_new_keypair()
        let target = ZapTarget.profile(keypair.pubkey)

        guard let nwcUrl = WalletConnectURL(str: "nostr+walletconnect://\(keypair.pubkey.hex())?relay=wss://relay.test&secret=\(keypair.privkey.hex())") else {
            XCTFail("Failed to create test WalletConnectURL")
            return
        }

        let nwcState = NWCPendingZapState(state: .confirmed, url: nwcUrl)
        let pendingZap = PendingZap(
            amount_msat: 10000,
            target: target,
            request: .normal(test_zap_request),
            type: .pub,
            state: .nwc(nwcState)
        )

        let zapping = Zapping.pending(pendingZap)

        // Confirmed NWC zaps should be considered paid
        XCTAssertTrue(zapping.is_paid)
        XCTAssertTrue(zapping.is_pending) // Still pending until we get the zap event
    }

    /// Test: remove_zap updates event totals when removing note zap
    @MainActor
    func test_remove_zap_updates_event_totals() throws {
        // Use fresh DamusState to avoid shared state issues
        let damus = generate_test_damus_state(mock_profile_info: nil)
        let noteId = test_note.id
        let target = ZapTarget.note(id: noteId, author: test_note.pubkey)

        // Create unique zap request for this test
        // Must use test_keypair so pubkey matches damus.our_pubkey for our_zaps lookup
        guard let zapReqEvent = NostrEvent(content: "test zap \(UUID())", keypair: test_keypair, kind: 9734) else {
            XCTFail("Failed to create zap request event")
            return
        }
        let zapRequest = ZapRequest(ev: zapReqEvent)

        // Create a pending zap with a specific amount
        let amount: Int64 = 50000
        let pendingZap = PendingZap(
            amount_msat: amount,
            target: target,
            request: .normal(zapRequest),
            type: .pub,
            state: .external(.init(state: .fetching_invoice))
        )

        // Add the zap - this should update totals
        damus.zaps.add_zap(zap: .pending(pendingZap))

        let totalBefore = damus.zaps.event_totals[noteId] ?? 0

        // Remove the zap - this should decrease totals
        let reqid = ZapRequestId(from_pending: pendingZap)
        _ = damus.zaps.remove_zap(reqid: reqid.reqid)

        let totalAfter = damus.zaps.event_totals[noteId] ?? 0
        XCTAssertEqual(totalAfter, totalBefore - amount)
    }

    /// Test: ZapsDataModel.confirm_nwc updates state correctly
    @MainActor
    func test_zaps_data_model_confirm_nwc() throws {
        let keypair = generate_new_keypair()
        let target = ZapTarget.profile(keypair.pubkey)

        guard let nwcUrl = WalletConnectURL(str: "nostr+walletconnect://\(keypair.pubkey.hex())?relay=wss://relay.test&secret=\(keypair.privkey.hex())") else {
            XCTFail("Failed to create test WalletConnectURL")
            return
        }

        // Create a mock NWC event to simulate postbox_pending state
        guard let nwcEvent = NostrEvent(content: "test", keypair: keypair.to_keypair(), kind: 23194) else {
            XCTFail("Failed to create NWC event")
            return
        }

        let nwcState = NWCPendingZapState(state: .postbox_pending(nwcEvent), url: nwcUrl)
        let pendingZap = PendingZap(
            amount_msat: 10000,
            target: target,
            request: .normal(test_zap_request),
            type: .pub,
            state: .nwc(nwcState)
        )

        let zapsModel = ZapsDataModel([.pending(pendingZap)])

        // Confirm the NWC zap
        zapsModel.confirm_nwc(reqid: test_zap_request.ev.id)

        // Verify state was updated to confirmed
        guard case .pending(let updatedPzap) = zapsModel.zaps.first,
              case .nwc(let updatedNwcState) = updatedPzap.state else {
            XCTFail("Expected pending zap with NWC state")
            return
        }

        XCTAssertTrue(updatedNwcState.state == NWCStateType.confirmed)
    }
}
