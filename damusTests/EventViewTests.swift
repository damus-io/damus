//
//  EventViewTests.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2023-10-13.
//

import Foundation
import XCTest
import SnapshotTesting
import SwiftUI
@testable import damus

final class EventViewTests: XCTestCase {
    
    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    func testBasicEventViewLayout() {
        let test_mock_damus_state = generate_test_damus_state(
            mock_profile_info: [
                // Manually mock some profile info so that we have a more realistic-looking note
                jack_keypair.pubkey: Profile(
                    name: "jack",
                    display_name: "Jack Dorsey"
                )
            ]
        )
        let test_note = NostrEvent(
            content: "Nostr is the super app. Because it’s actually an ecosystem of apps, all of which make each other better. People haven’t grasped that yet. They will when it’s more accessible and onboarding is more straightforward and intuitive.",
            keypair: jack_keypair,
            createdAt: UInt32(Date.init(timeIntervalSinceNow: -60).timeIntervalSince1970)
        )!
        
        let eventViewTest = EventView(damus: test_mock_damus_state, event: test_note).padding()
        let hostView = UIHostingController(rootView: eventViewTest)
        
        // Run snapshot check
        assertSnapshot(matching: hostView, as: .image(on: .iPhone13(.portrait)))
    }
}
