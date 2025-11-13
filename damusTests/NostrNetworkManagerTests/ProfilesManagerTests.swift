//
//  ProfilesManagerTests.swift
//  damusTests
//
//  Created by alltheseas on 2025-12-18.
//

import XCTest
@testable import damus


class ProfilesManagerTests: XCTestCase {

    /// Tests that streamProfile with yieldCached: true (default) immediately emits a cached profile.
    ///
    /// This verifies the fix for missing profile names/pictures: when a view subscribes to
    /// profile updates, it should immediately receive any cached profile data from NostrDB
    /// rather than waiting for the network subscription to restart (~1 second delay).
    func testStreamProfileYieldsCachedProfileByDefault() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        // Seed a profile into NDB
        let profilePubkey = test_keypair.pubkey
        let profileJson = """
        {"name":"testuser","display_name":"Test User","about":"A test profile","picture":"https://example.com/pic.jpg"}
        """
        let metadataEvent = NostrEvent(
            content: profileJson,
            keypair: test_keypair,
            kind: NostrKind.metadata.rawValue,
            tags: [],
            createdAt: UInt32(Date.now.timeIntervalSince1970)
        )!

        let eventJson = encode_json(metadataEvent)!
        let relayMessage = "[\"EVENT\",\"subid\",\(eventJson)]"
        let processed = ndb.processEvent(relayMessage)
        XCTAssertTrue(processed, "Failed to process metadata event")

        // Give NDB time to process
        try await Task.sleep(for: .milliseconds(100))

        // Verify profile is in NDB
        let cachedProfile = try? ndb.lookup_profile_and_copy(profilePubkey)
        XCTAssertNotNil(cachedProfile, "Profile should be cached in NDB")
        XCTAssertEqual(cachedProfile?.name, "testuser")

        // Create ProfilesManager and test streaming
        let pool = RelayPool(ndb: ndb, keypair: test_keypair)
        let subscriptionManager = NostrNetworkManager.SubscriptionManager(
            pool: pool,
            ndb: ndb,
            experimentalLocalRelayModelSupport: false
        )
        let profilesManager = NostrNetworkManager.ProfilesManager(
            subscriptionManager: subscriptionManager,
            ndb: ndb
        )

        // Test: yieldCached: true (default) should emit immediately
        let receivedProfile = XCTestExpectation(description: "Should receive cached profile immediately")
        var emittedProfile: NdbProfile?

        Task {
            // Default yieldCached: true
            for await profile in await profilesManager.streamProfile(pubkey: profilePubkey) {
                emittedProfile = profile
                receivedProfile.fulfill()
                break  // Only need the first emission
            }
        }

        // Should receive the profile very quickly (not waiting for network)
        await fulfillment(of: [receivedProfile], timeout: 0.5)

        XCTAssertNotNil(emittedProfile, "Should have received a profile")
        XCTAssertEqual(emittedProfile?.name, "testuser", "Should receive the cached profile data")
        XCTAssertEqual(emittedProfile?.display_name, "Test User")
    }

    /// Tests that streamProfile with yieldCached: false does NOT immediately emit cached profiles.
    ///
    /// This is used by callers like NoteContentView that only need network updates, not
    /// initial cached state, to avoid redundant artifact re-renders.
    func testStreamProfileOptOutSkipsCachedProfile() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        // Seed a profile into NDB
        let profilePubkey = test_keypair.pubkey
        let profileJson = """
        {"name":"testuser","display_name":"Test User","about":"A test profile"}
        """
        let metadataEvent = NostrEvent(
            content: profileJson,
            keypair: test_keypair,
            kind: NostrKind.metadata.rawValue,
            tags: [],
            createdAt: UInt32(Date.now.timeIntervalSince1970)
        )!

        let eventJson = encode_json(metadataEvent)!
        let relayMessage = "[\"EVENT\",\"subid\",\(eventJson)]"
        let processed = ndb.processEvent(relayMessage)
        XCTAssertTrue(processed, "Failed to process metadata event")

        // Give NDB time to process
        try await Task.sleep(for: .milliseconds(100))

        // Verify profile is in NDB
        let cachedProfile = try? ndb.lookup_profile_and_copy(profilePubkey)
        XCTAssertNotNil(cachedProfile, "Profile should be cached in NDB")

        // Create ProfilesManager
        let pool = RelayPool(ndb: ndb, keypair: test_keypair)
        let subscriptionManager = NostrNetworkManager.SubscriptionManager(
            pool: pool,
            ndb: ndb,
            experimentalLocalRelayModelSupport: false
        )
        let profilesManager = NostrNetworkManager.ProfilesManager(
            subscriptionManager: subscriptionManager,
            ndb: ndb
        )

        // Test: yieldCached: false should NOT emit immediately
        let shouldNotReceive = XCTestExpectation(description: "Should NOT receive cached profile")
        shouldNotReceive.isInverted = true  // We expect this to NOT be fulfilled

        Task {
            // Explicitly opt out of cached emission
            for await _ in await profilesManager.streamProfile(pubkey: profilePubkey, yieldCached: false) {
                shouldNotReceive.fulfill()  // This should NOT happen
                break
            }
        }

        // Wait briefly - the stream should NOT emit anything
        await fulfillment(of: [shouldNotReceive], timeout: 0.3)
        // If we get here without the expectation being fulfilled, the test passes
    }

    /// Tests that streamProfiles with yieldCached: true emits all cached profiles.
    func testStreamProfilesYieldsCachedProfilesByDefault() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        // Seed two profiles into NDB
        let pubkey1 = test_keypair.pubkey
        let pubkey2 = test_pubkey_2

        let profile1Json = "{\"name\":\"user1\",\"display_name\":\"User One\"}"
        let profile1Event = NostrEvent(
            content: profile1Json,
            keypair: test_keypair,
            kind: NostrKind.metadata.rawValue,
            tags: [],
            createdAt: UInt32(Date.now.timeIntervalSince1970)
        )!

        // For pubkey2, we need to create an event that appears to come from that pubkey
        // Since we can't sign for pubkey2, we'll just test with one profile

        let eventJson = encode_json(profile1Event)!
        let relayMessage = "[\"EVENT\",\"subid\",\(eventJson)]"
        let processed = ndb.processEvent(relayMessage)
        XCTAssertTrue(processed, "Failed to process metadata event")

        try await Task.sleep(for: .milliseconds(100))

        // Create ProfilesManager
        let pool = RelayPool(ndb: ndb, keypair: test_keypair)
        let subscriptionManager = NostrNetworkManager.SubscriptionManager(
            pool: pool,
            ndb: ndb,
            experimentalLocalRelayModelSupport: false
        )
        let profilesManager = NostrNetworkManager.ProfilesManager(
            subscriptionManager: subscriptionManager,
            ndb: ndb
        )

        // Test: yieldCached: true (default) should emit cached profiles
        let receivedProfile = XCTestExpectation(description: "Should receive cached profile")
        var emittedProfiles: [NdbProfile] = []

        Task {
            // Request both pubkeys, but only pubkey1 has a profile in NDB
            for await profile in await profilesManager.streamProfiles(pubkeys: Set([pubkey1, pubkey2])) {
                emittedProfiles.append(profile)
                receivedProfile.fulfill()
                break
            }
        }

        await fulfillment(of: [receivedProfile], timeout: 0.5)

        XCTAssertEqual(emittedProfiles.count, 1, "Should receive one cached profile")
        XCTAssertEqual(emittedProfiles.first?.name, "user1")
    }

    /// Tests that streamProfiles with yieldCached: false does NOT emit cached profiles.
    func testStreamProfilesOptOutSkipsCachedProfiles() async throws {
        let ndb = Ndb.test
        defer { ndb.close() }

        // Seed a profile into NDB
        let profilePubkey = test_keypair.pubkey
        let profileJson = "{\"name\":\"testuser\"}"
        let metadataEvent = NostrEvent(
            content: profileJson,
            keypair: test_keypair,
            kind: NostrKind.metadata.rawValue,
            tags: [],
            createdAt: UInt32(Date.now.timeIntervalSince1970)
        )!

        let eventJson = encode_json(metadataEvent)!
        let relayMessage = "[\"EVENT\",\"subid\",\(eventJson)]"
        ndb.processEvent(relayMessage)

        try await Task.sleep(for: .milliseconds(100))

        // Create ProfilesManager
        let pool = RelayPool(ndb: ndb, keypair: test_keypair)
        let subscriptionManager = NostrNetworkManager.SubscriptionManager(
            pool: pool,
            ndb: ndb,
            experimentalLocalRelayModelSupport: false
        )
        let profilesManager = NostrNetworkManager.ProfilesManager(
            subscriptionManager: subscriptionManager,
            ndb: ndb
        )

        // Test: yieldCached: false should NOT emit
        let shouldNotReceive = XCTestExpectation(description: "Should NOT receive cached profiles")
        shouldNotReceive.isInverted = true

        Task {
            for await _ in await profilesManager.streamProfiles(pubkeys: Set([profilePubkey]), yieldCached: false) {
                shouldNotReceive.fulfill()
                break
            }
        }

        await fulfillment(of: [shouldNotReceive], timeout: 0.3)
    }
}
