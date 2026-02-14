//
//  LoadableNostrEventViewModelTests.swift
//  damusTests
//
//  Created by alltheseas on 2026-02-13.
//

import XCTest
@testable import damus

/// Tests for LoadableNostrEventViewModel, verifying that event loading
/// waits for relay connection before attempting network lookups.
///
/// ## Bug replication (issue #3544)
///
/// Before the fix, `load()` called `executeLoadingLogic()` immediately
/// without waiting for relay connection. When the app opened a nevent URL
/// or search result before relays connected, `findEvent` would fail and
/// the view would show "not found."
///
/// The observable difference:
///
/// - **Old code** (no `awaitConnection`): `executeLoadingLogic` runs
///   immediately → `findEvent` hits empty ndb and disconnected relays →
///   returns nil → state becomes `.not_found` within milliseconds.
///
/// - **Fixed code** (with `awaitConnection`): `load()` blocks at
///   `awaitConnection()` → state stays `.loading` until relays connect
///   or the 30 s timeout fires.
///
/// The fix adds `awaitConnection()` before loading, matching the pattern
/// established in `SearchHomeModel.load()` (commit fa4b7a75).
@MainActor
final class LoadableNostrEventViewModelTests: XCTestCase {

    /// Proves the fix: without a relay connection, `load()` blocks at
    /// `awaitConnection()` and state remains `.loading`.
    ///
    /// **Fails with old code (the bug):** Without `awaitConnection()`,
    /// `executeLoadingLogic` runs immediately on disconnected relays.
    /// `findEvent` falls through to `streamExistingEvents` (10 s default
    /// timeout), which eventually returns nil → state becomes `.not_found`.
    ///
    /// **Passes with fix:** `awaitConnection()` blocks for up to 30 s,
    /// so state stays `.loading` well past the 11 s check window.
    ///
    /// The 11 s sleep exceeds the `streamExistingEvents` 10 s timeout,
    /// ensuring the old code path has fully resolved to `.not_found`.
    func testLoadBlocksUntilConnected() async throws {
        let state = generate_test_damus_state(mock_profile_info: nil)

        // Do NOT call connect() — simulates opening a nevent URL
        // before relays are ready (the exact bug scenario).
        let vm = LoadableNostrEventViewModel(
            damus_state: state,
            note_reference: .note_id(test_note.id, relays: [])
        )

        // Sleep past the 10 s streamExistingEvents timeout so the old
        // code path fully resolves, but under the 30 s awaitConnection
        // timeout so the fix keeps state at .loading.
        try await Task.sleep(for: .seconds(11))

        // With the fix: awaitConnection() is still blocking → .loading
        // Without the fix (bug): executeLoadingLogic completed → .not_found
        switch vm.state {
        case .loading:
            break  // Correct: awaitConnection is blocking as intended
        case .not_found:
            XCTFail("State is .not_found — load() bypassed awaitConnection and ran executeLoadingLogic on disconnected relays (bug #3544)")
        case .loaded:
            XCTFail("Should not load without a relay connection")
        case .unknown_or_unsupported_kind:
            XCTFail("Unexpected state")
        }
    }

    /// Verifies that `awaitConnection()` returns immediately when the
    /// network is already connected, so `load()` proceeds without delay.
    func testAwaitConnection_ReturnsImmediatelyWhenConnected() async throws {
        let state = generate_test_damus_state(mock_profile_info: nil)

        try! await state.nostrNetwork.userRelayList.set(userRelayList: NIP65.RelayList())
        await state.nostrNetwork.connect()

        let start = ContinuousClock.now
        await state.nostrNetwork.awaitConnection()
        let elapsed = ContinuousClock.now - start

        XCTAssertLessThan(elapsed, .seconds(1), "awaitConnection should return immediately when already connected")
    }

    /// Verifies that `awaitConnection()` respects its timeout and does
    /// not block indefinitely when no connection is established.
    func testAwaitConnectionTimeout_DoesNotBlockForever() async throws {
        let state = generate_test_damus_state(mock_profile_info: nil)

        let start = ContinuousClock.now
        await state.nostrNetwork.awaitConnection(timeout: .milliseconds(200))
        let elapsed = ContinuousClock.now - start

        XCTAssertLessThan(elapsed, .seconds(2), "awaitConnection should respect timeout")
    }
}
