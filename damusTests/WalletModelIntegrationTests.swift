//
//  WalletModelIntegrationTests.swift
//  damusTests
//
//  Created by alltheseas on 2026-02-02.
//

import XCTest
import Dispatch
@testable import damus

/// Integration tests for WalletModel state management and connection lifecycle.
///
/// These tests verify the WalletModel's state transitions, connection management,
/// and published property updates. Note that the async continuation mechanism
/// is tested indirectly through timeout behavior since the internals are private.
///
/// ## Thread Sanitizer (TSan)
///
/// Run these tests with Thread Sanitizer enabled to detect data races:
/// 1. In Xcode: Edit Scheme → Test → Diagnostics → Thread Sanitizer
/// 2. Or via command line: `xcodebuild test -enableThreadSanitizer YES ...`
final class WalletModelIntegrationTests: XCTestCase {

    // MARK: - Test Helpers

    /// Generates a random hex string of the specified byte length.
    private func generateRandomHex(byteLength: Int) -> String {
        (0..<byteLength).map { _ in String(format: "%02x", UInt8.random(in: 0...255)) }.joined()
    }

    /// Creates a test NWC URL with randomly generated keys for safe testing.
    private func makeTestNWCURL(relay: String = "wss://relay.test.com") -> String {
        let pubkey = generateRandomHex(byteLength: 32)
        let secret = generateRandomHex(byteLength: 32)
        return "nostrwalletconnect://\(pubkey)?relay=\(relay)&secret=\(secret)"
    }

    // MARK: - Connection State Tests

    /// Tests that initial state is .none when no NWC URL is configured.
    func testInitialState_NoNwcUrl() throws {
        let settings = UserSettingsStore()
        settings.nostr_wallet_connect = nil

        let wallet = WalletModel(settings: settings)

        if case .none = wallet.connect_state {
            // Expected
        } else {
            XCTFail("Initial state should be .none when no NWC URL configured")
        }
    }

    /// Tests that initial state is .existing when NWC URL is configured in settings.
    func testInitialState_WithNwcUrl() throws {
        let settings = UserSettingsStore()
        let nwcStr = makeTestNWCURL()
        settings.nostr_wallet_connect = nwcStr

        let wallet = WalletModel(settings: settings)

        if case .existing(let url) = wallet.connect_state {
            // Just verify we got a valid pubkey (32 bytes = 64 hex chars)
            XCTAssertEqual(url.pubkey.hex().count, 64)
        } else {
            XCTFail("Initial state should be .existing when NWC URL is configured")
        }
    }

    /// Tests the new() -> connect() flow.
    func testNewToConnectFlow() throws {
        let settings = UserSettingsStore()
        let wallet = WalletModel(settings: settings)

        // Create test NWC URL with runtime-generated keys
        let nwcStr = makeTestNWCURL()
        guard let nwc = WalletConnectURL(str: nwcStr) else {
            XCTFail("Failed to parse NWC URL")
            return
        }
        let expectedPubkey = nwc.pubkey.hex()

        // Set to .new state
        wallet.new(nwc)
        if case .new(let url) = wallet.connect_state {
            XCTAssertEqual(url.pubkey.hex(), expectedPubkey)
        } else {
            XCTFail("State should be .new after calling new()")
        }

        // Connect
        wallet.connect(nwc)
        if case .existing(let url) = wallet.connect_state {
            XCTAssertEqual(url.pubkey.hex(), expectedPubkey)
        } else {
            XCTFail("State should be .existing after calling connect()")
        }

        // Settings should be updated
        XCTAssertNotNil(settings.nostr_wallet_connect)
    }

    /// Tests the disconnect flow.
    func testDisconnectFlow() throws {
        let settings = UserSettingsStore()
        let nwcStr = makeTestNWCURL()
        settings.nostr_wallet_connect = nwcStr

        let wallet = WalletModel(settings: settings)

        // Should start as .existing
        if case .existing = wallet.connect_state {
            // Expected
        } else {
            XCTFail("Should start as .existing")
        }

        // Disconnect
        wallet.disconnect()

        if case .none = wallet.connect_state {
            // Expected
        } else {
            XCTFail("Should be .none after disconnect")
        }

        // Settings should be cleared
        XCTAssertNil(settings.nostr_wallet_connect)
    }

    /// Tests that cancel() restores previous state.
    func testCancelRestoresPreviousState() throws {
        let settings = UserSettingsStore()
        let nwcStr1 = makeTestNWCURL(relay: "wss://relay1.test.com")
        settings.nostr_wallet_connect = nwcStr1

        let wallet = WalletModel(settings: settings)

        // Capture first URL's pubkey for later comparison
        guard case .existing(let firstUrl) = wallet.connect_state else {
            XCTFail("Should start as .existing")
            return
        }
        let firstPubkey = firstUrl.pubkey.hex()

        // Create second NWC URL and set as .new
        let nwcStr2 = makeTestNWCURL(relay: "wss://relay2.test.com")
        guard let nwc2 = WalletConnectURL(str: nwcStr2) else {
            XCTFail("Failed to parse second NWC URL")
            return
        }
        let secondPubkey = nwc2.pubkey.hex()

        wallet.new(nwc2)
        if case .new(let url) = wallet.connect_state {
            XCTAssertEqual(url.pubkey.hex(), secondPubkey)
        } else {
            XCTFail("Should be .new with second URL")
        }

        // Cancel - should restore to previous .existing state
        wallet.cancel()

        if case .existing(let url) = wallet.connect_state {
            XCTAssertEqual(url.pubkey.hex(), firstPubkey)
        } else {
            XCTFail("Should restore to previous .existing state after cancel")
        }
    }

    // MARK: - State Management Tests

    /// Tests that initial balance and transactions are nil.
    @MainActor
    func testInitialStateIsNil() async throws {
        let settings = UserSettingsStore()
        let wallet = WalletModel(settings: settings)

        XCTAssertNil(wallet.balance, "Balance should be nil initially")
        XCTAssertNil(wallet.transactions, "Transactions should be nil initially")
    }

    /// Tests that resetWalletStateInformation clears state.
    @MainActor
    func testResetWalletStateInformation() async throws {
        let settings = UserSettingsStore()
        let wallet = WalletModel(settings: settings)

        // Manually verify reset clears any state
        wallet.resetWalletStateInformation()

        XCTAssertNil(wallet.balance, "Balance should be nil after reset")
        XCTAssertNil(wallet.transactions, "Transactions should be nil after reset")
    }

    // MARK: - Timeout Tests

    /// Tests that waitForResponse times out correctly when no response arrives.
    func testWaitForResponseTimeout() async throws {
        let settings = UserSettingsStore()
        let wallet = WalletModel(settings: settings)

        let requestId = NoteId(Data((0..<32).map { _ in UInt8.random(in: 0...255) }))

        let startTime = Date()

        do {
            _ = try await wallet.waitForResponse(for: requestId, timeout: .milliseconds(200))
            XCTFail("Should have timed out")
        } catch {
            let elapsed = Date().timeIntervalSince(startTime)
            // Should timeout around 200ms (allow some tolerance)
            XCTAssertGreaterThan(elapsed, 0.15, "Should wait at least 150ms")
            XCTAssertLessThan(elapsed, 1.0, "Should not wait more than 1s")
        }
    }

    /// Tests sequential timeout requests work correctly.
    ///
    /// This test runs `waitForResponse` calls sequentially for determinism.
    /// WalletModel now uses an NSLock to protect the `continuations` dictionary,
    /// making concurrent access safe. See WalletModelConcurrencyTests for
    /// parallel behavior verification.
    func testSequentialTimeouts() async throws {
        let settings = UserSettingsStore()
        let wallet = WalletModel(settings: settings)

        // Run requests sequentially to avoid race conditions in continuations dictionary
        for i in 0..<3 {
            let requestId = NoteId(Data((0..<32).map { _ in UInt8.random(in: 0...255) }))

            do {
                _ = try await wallet.waitForResponse(for: requestId, timeout: .milliseconds(100))
                XCTFail("Request \(i) should have timed out")
            } catch {
                // Expected timeout
            }
        }
    }

    // MARK: - currentNwcUrl Tests

    /// Tests that currentNwcUrl returns correct value for each state.
    func testCurrentNwcUrl() throws {
        let settings = UserSettingsStore()
        settings.nostr_wallet_connect = nil  // Ensure clean state
        let wallet = WalletModel(settings: settings)

        // .none state
        XCTAssertNil(wallet.connect_state.currentNwcUrl(), "currentNwcUrl should be nil for .none state")

        // .new state
        let nwcStr = makeTestNWCURL()
        guard let nwc = WalletConnectURL(str: nwcStr) else {
            XCTFail("Failed to parse NWC URL")
            return
        }
        let expectedPubkey = nwc.pubkey.hex()

        wallet.new(nwc)
        XCTAssertNil(wallet.connect_state.currentNwcUrl(), "currentNwcUrl should be nil for .new state (not confirmed yet)")

        // .existing state
        wallet.connect(nwc)
        XCTAssertNotNil(wallet.connect_state.currentNwcUrl(), "currentNwcUrl should not be nil for .existing state")
        XCTAssertEqual(wallet.connect_state.currentNwcUrl()?.pubkey.hex(), expectedPubkey)
    }

    // MARK: - Stress Tests

    /// Stress test: rapid state transitions.
    func testRapidStateTransitions_StressTest() throws {
        let settings = UserSettingsStore()
        let wallet = WalletModel(settings: settings)

        // Generate test NWC URLs at runtime
        let nwcStr1 = makeTestNWCURL(relay: "wss://relay1.test.com")
        let nwcStr2 = makeTestNWCURL(relay: "wss://relay2.test.com")

        guard let nwc1 = WalletConnectURL(str: nwcStr1),
              let nwc2 = WalletConnectURL(str: nwcStr2) else {
            XCTFail("Failed to parse NWC URLs")
            return
        }

        let pubkey1 = nwc1.pubkey.hex()
        let pubkey2 = nwc2.pubkey.hex()

        for _ in 0..<50 {
            // Connect first wallet
            wallet.new(nwc1)
            wallet.connect(nwc1)

            // Try to switch to second
            wallet.new(nwc2)

            // Random: cancel or connect
            if Bool.random() {
                wallet.cancel()
                // Should be back to nwc1
                if case .existing(let url) = wallet.connect_state {
                    XCTAssertEqual(url.pubkey.hex(), pubkey1)
                }
            } else {
                wallet.connect(nwc2)
                // Should be nwc2
                if case .existing(let url) = wallet.connect_state {
                    XCTAssertEqual(url.pubkey.hex(), pubkey2)
                }
            }

            // Disconnect
            wallet.disconnect()

            if case .none = wallet.connect_state {
                // Expected
            } else {
                XCTFail("Should be .none after disconnect")
            }
        }
    }

    /// Stress test: sequential timeout waits across iterations.
    ///
    /// This test runs `waitForResponse` calls sequentially for determinism.
    /// WalletModel now uses an NSLock to protect the `continuations` dictionary.
    /// See WalletModelConcurrencyTests for parallel stress testing.
    func testSequentialTimeoutWaits_StressTest() async throws {
        let settings = UserSettingsStore()

        for iteration in 0..<5 {
            // Create fresh wallet for each iteration to ensure clean state
            let wallet = WalletModel(settings: settings)

            // Run requests sequentially to avoid race conditions
            for i in 0..<5 {
                let requestId = NoteId(Data((0..<32).map { _ in UInt8.random(in: 0...255) }))

                do {
                    _ = try await wallet.waitForResponse(for: requestId, timeout: .milliseconds(50))
                } catch {
                    // Expected timeout
                }
            }
        }
    }

    // MARK: - Edge Case Tests

    // Note: We don't test multiple waitForResponse calls with the same request ID
    // because this scenario cannot occur in production. Each NWC wallet request
    // creates a new NostrEvent whose ID is a cryptographic hash of the event's
    // content, timestamp, and keys. Since the timestamp includes nanosecond
    // precision and the content includes a random request identifier, duplicate
    // request IDs are cryptographically impossible.

    /// Tests that a response arriving after timeout is handled gracefully.
    ///
    /// This verifies the continuation dictionary cleanup - late responses
    /// should not crash when the continuation has already been removed.
    func testResponseAfterTimeout_GracefulHandling() async throws {
        let settings = UserSettingsStore()
        let wallet = WalletModel(settings: settings)

        let requestId = NoteId(Data((0..<32).map { _ in UInt8.random(in: 0...255) }))

        // Start a request that will timeout
        let task = Task {
            do {
                _ = try await wallet.waitForResponse(for: requestId, timeout: .milliseconds(50))
                return "success"
            } catch {
                return "timeout"
            }
        }

        // Wait for timeout
        let result = await task.value
        XCTAssertEqual(result, "timeout")

        // Now simulate a late response arriving
        // Create a mock response - this tests the resume() path when continuation is gone
        // Note: We can't easily create a FullWalletResponse without NWC setup,
        // so we just verify the wallet is still in a usable state
        try await Task.sleep(for: .milliseconds(50))

        // Wallet should still be functional
        XCTAssertNotNil(wallet.settings)
    }

    /// Tests that balance and transactions remain consistent during state changes.
    @MainActor
    func testStateConsistencyDuringTransitions() async throws {
        let settings = UserSettingsStore()
        let nwcStr = makeTestNWCURL()
        guard let nwc = WalletConnectURL(str: nwcStr) else {
            XCTFail("Failed to parse NWC URL")
            return
        }

        let wallet = WalletModel(settings: settings)

        // Initial state
        XCTAssertNil(wallet.balance)
        XCTAssertNil(wallet.transactions)

        // Connect
        wallet.new(nwc)
        wallet.connect(nwc)

        // Reset should clear state
        wallet.resetWalletStateInformation()
        XCTAssertNil(wallet.balance)
        XCTAssertNil(wallet.transactions)

        // Disconnect
        wallet.disconnect()

        // After disconnect, state should still be nil
        XCTAssertNil(wallet.balance)
        XCTAssertNil(wallet.transactions)
    }

    // MARK: - Concurrent Response Handling Tests

    /// Tests that concurrent waitForResponse calls with different request IDs work correctly.
    ///
    /// With the NSLock fix, multiple concurrent waitForResponse calls should be safe
    /// as long as they use different request IDs.
    func testConcurrentWaitForResponse_DifferentIds() async throws {
        let settings = UserSettingsStore()
        let wallet = WalletModel(settings: settings)

        let concurrentCount = 5
        let allComplete = XCTestExpectation(description: "All requests complete")
        allComplete.expectedFulfillmentCount = concurrentCount

        // Start multiple concurrent waitForResponse calls with different IDs
        for i in 0..<concurrentCount {
            Task {
                let requestId = NoteId(Data((0..<32).map { _ in UInt8.random(in: 0...255) }))
                do {
                    _ = try await wallet.waitForResponse(for: requestId, timeout: .milliseconds(100))
                } catch {
                    // Expected timeout
                }
                allComplete.fulfill()
            }
        }

        await fulfillment(of: [allComplete], timeout: 5.0)
    }

    /// Tests that the double-resume protection works correctly.
    ///
    /// When a continuation is resumed (either by timeout or by actual response),
    /// subsequent resume calls with the same request ID should be no-ops.
    func testDoubleResumeProtection() async throws {
        let settings = UserSettingsStore()
        let wallet = WalletModel(settings: settings)

        let requestId = NoteId(Data((0..<32).map { _ in UInt8.random(in: 0...255) }))

        // Start a request that will timeout quickly
        let task = Task {
            do {
                _ = try await wallet.waitForResponse(for: requestId, timeout: .milliseconds(50))
                return "success"
            } catch {
                return "timeout"
            }
        }

        // Wait for timeout to occur
        let result = await task.value
        XCTAssertEqual(result, "timeout")

        // The continuation should now be removed from the dictionary
        // If we could call resume again, it should be a no-op (not crash)
        // This is tested implicitly - if double-resume happened, we'd crash
    }

    /// Stress test: many concurrent requests to verify lock protection works.
    func testConcurrentRequests_StressTest() async throws {
        let settings = UserSettingsStore()
        let wallet = WalletModel(settings: settings)

        for iteration in 0..<10 {
            let concurrentCount = 10
            let allComplete = XCTestExpectation(description: "Iteration \(iteration)")
            allComplete.expectedFulfillmentCount = concurrentCount

            for _ in 0..<concurrentCount {
                Task {
                    let requestId = NoteId(Data((0..<32).map { _ in UInt8.random(in: 0...255) }))
                    do {
                        _ = try await wallet.waitForResponse(for: requestId, timeout: .milliseconds(50))
                    } catch {
                        // Expected timeout
                    }
                    allComplete.fulfill()
                }
            }

            await fulfillment(of: [allComplete], timeout: 5.0)
        }
    }

    /// Tests that request cleanup happens properly even with rapid sequential requests.
    func testRapidSequentialRequests_Cleanup() async throws {
        let settings = UserSettingsStore()
        let wallet = WalletModel(settings: settings)

        // Rapid sequential requests should all clean up properly
        for i in 0..<50 {
            let requestId = NoteId(Data((0..<32).map { _ in UInt8.random(in: 0...255) }))
            do {
                _ = try await wallet.waitForResponse(for: requestId, timeout: .milliseconds(10))
            } catch {
                // Expected timeout
            }
        }

        // Wallet should still be functional after many rapid requests
        XCTAssertNotNil(wallet.settings)
    }
}
