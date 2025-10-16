//
//  MutingTests.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2024-05-06.
//
import Foundation

import XCTest
@testable import damus

final class MutingTests: XCTestCase {
    func testWordMuting() {
        // Setup some test data
        let test_note = NostrEvent(
            content: "Nostr is the super app. Because it's actually an ecosystem of apps, all of which make each other better. People haven't grasped that yet. They will when it's more accessible and onboarding is more straightforward and intuitive.",
            keypair: jack_keypair,
            createdAt: UInt32(Date().timeIntervalSince1970 - 100)
        )!
        let spammy_keypair = generate_new_keypair().to_keypair()
        let spammy_test_note = NostrEvent(
            content: "Some spammy airdrop just arrived! Why stack sats when you can get scammed instead with some random coin? Call 1-800-GET-SCAMMED to claim your airdrop today!",
            keypair: spammy_keypair,
            createdAt: UInt32(Date().timeIntervalSince1970 - 100)
        )!

        let mute_item: MuteItem = .word("airdrop", nil)
        let existing_mutelist = test_damus_state.mutelist_manager.event

        guard
            let full_keypair = test_damus_state.keypair.to_full(),
            let mutelist = create_or_update_mutelist(keypair: full_keypair, mprev: existing_mutelist, to_add: mute_item)
        else {
            return
        }

        test_damus_state.mutelist_manager.set_mutelist(mutelist)
        test_damus_state.nostrNetwork.postbox.send(mutelist)

        XCTAssert(test_damus_state.mutelist_manager.is_event_muted(spammy_test_note))
        XCTAssertFalse(test_damus_state.mutelist_manager.is_event_muted(test_note))
    }

    func testTemporaryMutePersistence() {
        // Test that temporary mutes are stored in the mutelist event even if they haven't expired yet
        let spammy_keypair = generate_new_keypair().to_keypair()
        let expiration_date = Calendar.current.date(byAdding: .hour, value: 24, to: Date())

        // Create a temporary mute that expires in 24 hours
        let temp_mute_item: MuteItem = .user(spammy_keypair.pubkey, expiration_date)
        let existing_mutelist = test_damus_state.mutelist_manager.event

        guard
            let full_keypair = test_damus_state.keypair.to_full(),
            let mutelist = create_or_update_mutelist(keypair: full_keypair, mprev: existing_mutelist, to_add: temp_mute_item)
        else {
            XCTFail("Failed to create mutelist")
            return
        }

        // Verify the mutelist contains the temporary mute
        XCTAssertNotNil(mutelist.mute_list, "Mutelist should exist")
        XCTAssertTrue(mutelist.mute_list!.contains(temp_mute_item), "Mutelist should contain the temporary mute item")

        // Simulate app restart by creating a new mutelist manager and loading the mutelist
        let new_manager = MutelistManager(user_keypair: test_damus_state.keypair)
        new_manager.set_mutelist(mutelist)

        // Verify the temporary mute is still in the manager
        XCTAssertTrue(new_manager.is_muted(temp_mute_item), "Temporary mute should persist after reload")
    }

    func testExpiredMuteNotActive() {
        // Test that expired mutes are stored but not active
        let spammy_keypair = generate_new_keypair().to_keypair()
        // Create an expiration date in the past
        let expiration_date = Calendar.current.date(byAdding: .hour, value: -1, to: Date())

        // Create a temporary mute that already expired
        let expired_mute_item: MuteItem = .user(spammy_keypair.pubkey, expiration_date)
        let existing_mutelist = test_damus_state.mutelist_manager.event

        guard
            let full_keypair = test_damus_state.keypair.to_full(),
            let mutelist = create_or_update_mutelist(keypair: full_keypair, mprev: existing_mutelist, to_add: expired_mute_item)
        else {
            XCTFail("Failed to create mutelist")
            return
        }

        // Set the mutelist
        test_damus_state.mutelist_manager.set_mutelist(mutelist)

        // Verify the expired mute is NOT active
        XCTAssertFalse(test_damus_state.mutelist_manager.is_muted(expired_mute_item), "Expired mute should not be active")
    }
}
