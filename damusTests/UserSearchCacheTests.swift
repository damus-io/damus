//
//  UserSearchCacheTests.swift
//  damusTests
//
//  Created by Terry Yiu on 6/30/23.
//

import XCTest
@testable import damus

// TODO: Update these tests to work with NostrDB Profile changes (https://github.com/damus-io/damus/issues/1586)
final class UserSearchCacheTests: XCTestCase {
    /*
    var keypair: FullKeypair? = nil
    let damusState = test_damus_state
    let nip05 = "_@somedomain.com"

    @MainActor
    override func setUpWithError() throws {
        keypair = try XCTUnwrap(generate_new_keypair())

        if let keypair {
            let pubkey = keypair.pubkey
            let validatedNip05 = try XCTUnwrap(NIP05.parse(nip05))

            damusState.profiles.set_validated(pubkey, nip05: validatedNip05)

            let profile = Profile(name: "tyiu", display_name: "Terry Yiu", about: nil, picture: nil, banner: nil, website: nil, lud06: nil, lud16: nil, nip05: nip05, damus_donation: nil)

            // Lookup to synchronize access on profiles dictionary to avoid race conditions.
            let _ = damusState.profiles.lookup(id: pubkey)
        }
    }

    override func tearDown() {
        keypair = nil
    }

    func testSearch() throws {
        let keypair = try XCTUnwrap(keypair)
        XCTAssertEqual(damusState.user_search_cache.search(key: "tyiu"), [keypair.pubkey])
        XCTAssertEqual(damusState.user_search_cache.search(key: "ty"), [keypair.pubkey])
        XCTAssertEqual(damusState.user_search_cache.search(key: "terry yiu"), [keypair.pubkey])
        XCTAssertEqual(damusState.user_search_cache.search(key: "rry"), [keypair.pubkey])
        XCTAssertEqual(damusState.user_search_cache.search(key: "somedomain"), [keypair.pubkey])
        XCTAssertEqual(damusState.user_search_cache.search(key: "dom"), [keypair.pubkey])
        XCTAssertEqual(damusState.user_search_cache.search(key: "i"), [keypair.pubkey])
    }

    @MainActor
    func testUpdateProfile() throws {
        let keypair = try XCTUnwrap(keypair)

        let newNip05 = "_@other.xyz"
        _ = try XCTUnwrap(NIP05.parse(newNip05))

        damusState.profiles.set_validated(keypair.pubkey, nip05: NIP05.parse(newNip05))

        // Old profile attributes are removed from cache.
        XCTAssertEqual(damusState.user_search_cache.search(key: "tyiu"), [])
        XCTAssertEqual(damusState.user_search_cache.search(key: "ty"), [])
        XCTAssertEqual(damusState.user_search_cache.search(key: "Terry Yiu"), [])
        XCTAssertEqual(damusState.user_search_cache.search(key: "rry"), [])
        XCTAssertEqual(damusState.user_search_cache.search(key: "somedomain"), [])
        XCTAssertEqual(damusState.user_search_cache.search(key: "dom"), [])

        // New profile attributes are added to cache.
        XCTAssertEqual(damusState.user_search_cache.search(key: "whoami"), [keypair.pubkey])
        XCTAssertEqual(damusState.user_search_cache.search(key: "hoa"), [keypair.pubkey])
        XCTAssertEqual(damusState.user_search_cache.search(key: "t-dawg"), [keypair.pubkey])
        XCTAssertEqual(damusState.user_search_cache.search(key: "daw"), [keypair.pubkey])
        XCTAssertEqual(damusState.user_search_cache.search(key: "other"), [keypair.pubkey])
        XCTAssertEqual(damusState.user_search_cache.search(key: "xyz"), [keypair.pubkey])
        XCTAssertEqual(damusState.user_search_cache.search(key: "the"), [keypair.pubkey])
        XCTAssertEqual(damusState.user_search_cache.search(key: "y"), [keypair.pubkey])
    }
    */

    /*
    func testUpdateOwnContactsPetnames() throws {
        let keypair = try XCTUnwrap(keypair)
        let damus = Pubkey(hex: "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681")!
        let jb55 = Pubkey(hex: "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245")!

        var pubkeysToPetnames = [Pubkey: String]()
        pubkeysToPetnames[damus] = "damus"
        pubkeysToPetnames[jb55] = "jb55"

        let contactsEvent = try createContactsEventWithPetnames(pubkeysToPetnames: pubkeysToPetnames)

        // Initial own contacts event caching on searchable petnames.
        damusState.user_search_cache.updateOwnContactsPetnames(id: keypair.pubkey, oldEvent: nil, newEvent: contactsEvent)

        XCTAssertEqual(damusState.user_search_cache.search(key: "damus"), [damus])
        XCTAssertEqual(damusState.user_search_cache.search(key: "jb55"), [jb55])
        XCTAssertEqual(damusState.user_search_cache.search(key: "5"), [jb55])

        // Replace one of the petnames and verify if the cache updates accordingly.

        pubkeysToPetnames.removeValue(forKey: jb55)
        pubkeysToPetnames[jb55] = "bill"
        let newContactsEvent = try createContactsEventWithPetnames(pubkeysToPetnames: pubkeysToPetnames)

        damusState.user_search_cache.updateOwnContactsPetnames(id: keypair.pubkey, oldEvent: contactsEvent, newEvent: newContactsEvent)

        XCTAssertEqual(damusState.user_search_cache.search(key: "damus"), [damus])
        XCTAssertEqual(damusState.user_search_cache.search(key: "jb55"), [])
        XCTAssertEqual(damusState.user_search_cache.search(key: "5"), [])
        XCTAssertEqual(damusState.user_search_cache.search(key: "bill"), [jb55])
        XCTAssertEqual(damusState.user_search_cache.search(key: "l"), [jb55])
    }
    */

    /*
    private func createContactsEventWithPetnames(pubkeysToPetnames: [Pubkey: String]) throws -> NostrEvent {
        let keypair = try XCTUnwrap(keypair)

        let bootstrapRelays = load_bootstrap_relays(pubkey: keypair.pubkey)
        let relayInfo = RelayInfo(read: true, write: true)
        var relays: [String: RelayInfo] = [:]

        for relay in bootstrapRelays {
            relays[relay] = relayInfo
        }

        let relayJson = encode_json(relays)!

        let tags: [[String]] = pubkeysToPetnames.enumerated().map {
            ["p", $0.element.key.description, "", $0.element.value]
        }

        return NostrEvent(content: relayJson, keypair: keypair.to_keypair(), kind: NostrKind.contacts.rawValue, tags: tags)!
    }
     */

}
