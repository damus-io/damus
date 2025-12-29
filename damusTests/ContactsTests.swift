//
//  ContactsTests.swift
//  damusTests
//
//  Tests for the Contacts class, particularly focusing on thread-safety
//  to prevent race conditions during concurrent access (e.g., "Follow All" in onboarding).
//

import XCTest
@testable import damus

final class ContactsTests: XCTestCase {

    // MARK: - Basic Functionality Tests

    func testInitialization() {
        // Given/When: Creating a new Contacts instance
        let pubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let contacts = Contacts(our_pubkey: pubkey)

        // Then: Should have empty friend list and correct pubkey
        XCTAssertTrue(contacts.get_friend_list().isEmpty)
        XCTAssertEqual(contacts.our_pubkey, pubkey)
        XCTAssertNil(contacts.event)
    }

    func testAddFriendPubkey() {
        // Given: A Contacts instance
        let ourPubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let contacts = Contacts(our_pubkey: ourPubkey)
        let friendPubkey = Pubkey(hex: "5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e")!

        // When: Adding a friend pubkey
        contacts.add_friend_pubkey(friendPubkey)

        // Then: Should be in friend list and is_friend should return true
        XCTAssertTrue(contacts.is_friend(friendPubkey))
        XCTAssertEqual(contacts.get_friend_list().count, 1)
    }

    func testRemoveFriend() {
        // Given: A Contacts instance with a friend
        let ourPubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let contacts = Contacts(our_pubkey: ourPubkey)
        let friendPubkey = Pubkey(hex: "5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e")!
        contacts.add_friend_pubkey(friendPubkey)
        XCTAssertTrue(contacts.is_friend(friendPubkey))

        // When: Removing the friend
        contacts.remove_friend(friendPubkey)

        // Then: Should no longer be a friend
        XCTAssertFalse(contacts.is_friend(friendPubkey))
        XCTAssertTrue(contacts.get_friend_list().isEmpty)
    }

    func testIsFriendOrSelf_WithSelf() {
        // Given: A Contacts instance
        let ourPubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let contacts = Contacts(our_pubkey: ourPubkey)

        // When/Then: Checking if our own pubkey is friend or self
        XCTAssertTrue(contacts.is_friend_or_self(ourPubkey))
    }

    func testIsFriendOrSelf_WithFriend() {
        // Given: A Contacts instance with a friend
        let ourPubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let contacts = Contacts(our_pubkey: ourPubkey)
        let friendPubkey = Pubkey(hex: "5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e")!
        contacts.add_friend_pubkey(friendPubkey)

        // When/Then: Checking if friend is friend or self
        XCTAssertTrue(contacts.is_friend_or_self(friendPubkey))
    }

    func testFollowState() {
        // Given: A Contacts instance
        let ourPubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let contacts = Contacts(our_pubkey: ourPubkey)
        let friendPubkey = Pubkey(hex: "5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e")!
        let strangePubkey = Pubkey(hex: "e8ad060ec0e512bc8d8bb0a4149f7aec4e57e6c2ba4fd1eee70f241cce10a3b6")!
        contacts.add_friend_pubkey(friendPubkey)

        // When/Then: Checking follow state
        XCTAssertEqual(contacts.follow_state(friendPubkey), .follows)
        XCTAssertEqual(contacts.follow_state(strangePubkey), .unfollows)
    }

    // MARK: - Thread Safety Tests

    /// Tests that concurrent add_friend_pubkey calls don't crash.
    /// This is the primary regression test for the "Follow All" crash fix.
    func testConcurrentAddFriendPubkey_DoesNotCrash() {
        // Given: A Contacts instance and many pubkeys to add concurrently
        let ourPubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let contacts = Contacts(our_pubkey: ourPubkey)

        let pubkeysToAdd = (0..<100).compactMap { i -> Pubkey? in
            // Generate deterministic pubkeys for testing
            let hex = String(format: "%064x", i + 1)
            return Pubkey(hex: hex)
        }

        let expectation = self.expectation(description: "All concurrent adds complete")
        expectation.expectedFulfillmentCount = pubkeysToAdd.count

        // When: Adding all pubkeys concurrently from multiple threads
        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)
        for pubkey in pubkeysToAdd {
            queue.async {
                contacts.add_friend_pubkey(pubkey)
                expectation.fulfill()
            }
        }

        // Then: Should complete without crashing
        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(error, "Concurrent adds timed out")
        }

        // Verify all pubkeys were added
        let friendList = contacts.get_friend_list()
        XCTAssertEqual(friendList.count, pubkeysToAdd.count)
    }

    /// Tests that concurrent reads and writes don't crash.
    func testConcurrentReadWrite_DoesNotCrash() {
        // Given: A Contacts instance
        let ourPubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let contacts = Contacts(our_pubkey: ourPubkey)

        let testPubkey = Pubkey(hex: "5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e")!

        let iterations = 1000
        let expectation = self.expectation(description: "All concurrent operations complete")
        expectation.expectedFulfillmentCount = iterations * 2

        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

        // When: Performing concurrent reads and writes
        for _ in 0..<iterations {
            // Writer
            queue.async {
                contacts.add_friend_pubkey(testPubkey)
                expectation.fulfill()
            }

            // Reader
            queue.async {
                _ = contacts.is_friend(testPubkey)
                _ = contacts.get_friend_list()
                expectation.fulfill()
            }
        }

        // Then: Should complete without crashing
        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(error, "Concurrent read/write timed out")
        }
    }

    /// Tests that concurrent event property access is thread-safe.
    func testConcurrentEventAccess_DoesNotCrash() {
        // Given: A Contacts instance
        let ourPubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let contacts = Contacts(our_pubkey: ourPubkey)

        let iterations = 500
        let expectation = self.expectation(description: "All concurrent event operations complete")
        expectation.expectedFulfillmentCount = iterations * 2

        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

        // Create a test event
        let testEvent = NostrEvent(
            content: "test",
            keypair: Keypair(pubkey: ourPubkey, privkey: nil),
            kind: NostrKind.contacts.rawValue,
            tags: []
        )!

        // When: Performing concurrent reads and writes to event property
        for _ in 0..<iterations {
            // Writer
            queue.async {
                contacts.event = testEvent
                expectation.fulfill()
            }

            // Reader
            queue.async {
                _ = contacts.event
                expectation.fulfill()
            }
        }

        // Then: Should complete without crashing
        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(error, "Concurrent event access timed out")
        }
    }

    /// Tests the friend_filter closure is thread-safe when used concurrently.
    func testFriendFilter_ConcurrentAccess_DoesNotCrash() {
        // Given: A Contacts instance with some friends
        let ourPubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let contacts = Contacts(our_pubkey: ourPubkey)
        let friendPubkey = Pubkey(hex: "5b0183ab6c3e322bf4d41c6b3aef98562a144847b7499543727c5539a114563e")!
        contacts.add_friend_pubkey(friendPubkey)

        // Create a test event
        let testEvent = NostrEvent(
            content: "test",
            keypair: Keypair(pubkey: friendPubkey, privkey: nil),
            kind: NostrKind.text.rawValue,
            tags: []
        )!

        let filter = contacts.friend_filter

        let iterations = 500
        let expectation = self.expectation(description: "All filter operations complete")
        expectation.expectedFulfillmentCount = iterations

        let queue = DispatchQueue(label: "test.concurrent", attributes: .concurrent)

        // When: Using the filter concurrently
        for _ in 0..<iterations {
            queue.async {
                _ = filter(testEvent)
                expectation.fulfill()
            }
        }

        // Then: Should complete without crashing
        waitForExpectations(timeout: 10) { error in
            XCTAssertNil(error, "Concurrent filter access timed out")
        }
    }

    // MARK: - Delegate Tests

    func testDelegate_CalledOnEventChange() {
        // Given: A Contacts instance with a delegate
        let ourPubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let contacts = Contacts(our_pubkey: ourPubkey)
        let mockDelegate = MockContactsDelegate()
        contacts.delegate = mockDelegate

        // Create a test event
        let testEvent = NostrEvent(
            content: "test",
            keypair: Keypair(pubkey: ourPubkey, privkey: nil),
            kind: NostrKind.contacts.rawValue,
            tags: []
        )!

        // When: Setting the event
        contacts.event = testEvent

        // Then: Delegate should be notified
        XCTAssertTrue(mockDelegate.didReceiveEventChange)
        XCTAssertEqual(mockDelegate.lastEvent?.id, testEvent.id)
    }

    func testDelegate_NotCalledOnNilEvent() {
        // Given: A Contacts instance with a delegate and existing event
        let ourPubkey = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!
        let contacts = Contacts(our_pubkey: ourPubkey)
        let mockDelegate = MockContactsDelegate()
        contacts.delegate = mockDelegate

        // When: Setting event to nil
        contacts.event = nil

        // Then: Delegate should NOT be notified
        XCTAssertFalse(mockDelegate.didReceiveEventChange)
    }
}

// MARK: - Test Helpers

private class MockContactsDelegate: ContactsDelegate {
    var didReceiveEventChange = false
    var lastEvent: NostrEvent?

    func latest_contact_event_changed(new_event: NostrEvent) {
        didReceiveEventChange = true
        lastEvent = new_event
    }
}
