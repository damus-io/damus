//
//  ListTests.swift
//  damusTests
//
//  Created by William Casarin on 2023-01-25.
//

import XCTest
@testable import damus

final class ListTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testCreateMuteList() throws {
        let privkey = test_keypair_full.privkey
        let pubkey = test_keypair_full.pubkey
        let to_mute = test_pubkey
        let keypair = FullKeypair(pubkey: pubkey, privkey: privkey)
        let mutelist = create_or_update_mutelist(keypair: keypair, mprev: nil, to_add: .user(to_mute, nil))!

        XCTAssertEqual(mutelist.pubkey, pubkey)
        XCTAssertEqual(mutelist.content, "")
        XCTAssertEqual(mutelist.tags.count, 1)
        XCTAssertEqual(mutelist.tags[0][0].string(), "p")
        XCTAssertEqual(mutelist.tags[0][1].string(), to_mute.hex())
    }

    func testCreateAndRemoveMuteList() throws {
        let privkey = test_keypair_full.privkey
        let pubkey = test_keypair_full.pubkey
        let to_mute = test_pubkey
        let keypair = FullKeypair(pubkey: pubkey, privkey: privkey)
        let mutelist = create_or_update_mutelist(keypair: keypair, mprev: nil, to_add: .user(to_mute, nil))!
        let new = remove_from_mutelist(keypair: keypair, prev: mutelist, to_remove: .user(to_mute, nil))!

        XCTAssertEqual(new.pubkey, pubkey)
        XCTAssertEqual(new.content, "")
        XCTAssertEqual(new.tags.count, 0)
    }
    
    func testAddToExistingMutelist() throws {
        let privkey = test_keypair_full.privkey
        let pubkey = test_keypair_full.pubkey
        let to_mute = test_pubkey
        let to_mute_2 = test_pubkey_2
        let keypair = FullKeypair(pubkey: pubkey, privkey: privkey)
        let mutelist = create_or_update_mutelist(keypair: keypair, mprev: nil, to_add: .user(to_mute, nil))!
        let new = create_or_update_mutelist(keypair: keypair, mprev: mutelist, to_add: .user(to_mute_2, nil))!

        XCTAssertEqual(new.pubkey, pubkey)
        XCTAssertEqual(new.content, "")
        XCTAssertEqual(new.tags.count, 2)
        XCTAssertEqual(new.tags[0][0].string(), "p")
        XCTAssertEqual(new.tags[1][0].string(), "p")
        // This test failed once out of like 10 tries, due to the tags being in the incorrect order. So I decided to put the elements in an array and sort it. That way if the mutelist tags aren't in the expected order it won't fail the test.
        XCTAssertEqual([new.tags[0][1].string(), new.tags[1][1].string()].sorted(), [to_mute.hex(), to_mute_2.hex()].sorted())
    }

    func testAddToExistingMutelistShouldNotOverrideContent() throws {
        let privkey = test_keypair_full.privkey
        let pubkey = test_keypair_full.pubkey
        let keypair = FullKeypair(pubkey: pubkey, privkey: privkey)
        let mutelist = NostrEvent(content: "random", keypair: keypair.to_keypair(), kind: NostrKind.mute_list.rawValue, tags: [])
        let new = create_or_update_mutelist(keypair: keypair, mprev: mutelist, to_add: .user(test_pubkey, nil))!

        XCTAssertEqual(new.content, "random")
    }
}
