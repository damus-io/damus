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
            content: "Nostr is the super app. Because it’s actually an ecosystem of apps, all of which make each other better. People haven’t grasped that yet. They will when it’s more accessible and onboarding is more straightforward and intuitive.",
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
        test_damus_state.postbox.send(mutelist)
        
        XCTAssert(test_damus_state.mutelist_manager.is_event_muted(spammy_test_note))
        XCTAssertFalse(test_damus_state.mutelist_manager.is_event_muted(test_note))
    }
}
