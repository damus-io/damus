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
        let mutelist = create_or_update_mutelist(keypair: keypair, mprev: nil, to_add: .pubkey(to_mute))!

        XCTAssertEqual(mutelist.pubkey, pubkey)
        XCTAssertEqual(mutelist.content, "")
        XCTAssertEqual(mutelist.tags.count, 2)
        XCTAssertEqual(mutelist.tags[0][0].string(), "d")
        XCTAssertEqual(mutelist.tags[0][1].string(), "mute")
        XCTAssertEqual(mutelist.tags[1][0].string(), "p")
        XCTAssertEqual(mutelist.tags[1][1].string(), to_mute.hex())
    }

    func testCreateAndRemoveMuteList() throws {
        let privkey = test_keypair_full.privkey
        let pubkey = test_keypair_full.pubkey
        let to_mute = test_pubkey
        let keypair = FullKeypair(pubkey: pubkey, privkey: privkey)
        let mutelist = create_or_update_mutelist(keypair: keypair, mprev: nil, to_add: .pubkey(to_mute))!
        let new = remove_from_mutelist(keypair: keypair, prev: mutelist, to_remove: .pubkey(to_mute))!

        XCTAssertEqual(new.pubkey, pubkey)
        XCTAssertEqual(new.content, "")
        XCTAssertEqual(new.tags.count, 1)
        XCTAssertEqual(new.tags[0][0].string(), "d")
        XCTAssertEqual(new.tags[0][1].string(), "mute")
    }
    
    func testAddToExistingMutelist() throws {
        let privkey = test_keypair_full.privkey
        let pubkey = test_keypair_full.pubkey
        let to_mute = test_pubkey
        let to_mute_2 = test_pubkey_2
        let keypair = FullKeypair(pubkey: pubkey, privkey: privkey)
        let mutelist = create_or_update_mutelist(keypair: keypair, mprev: nil, to_add: .pubkey(to_mute))!
        let new = create_or_update_mutelist(keypair: keypair, mprev: mutelist, to_add: .pubkey(to_mute_2))!

        XCTAssertEqual(new.pubkey, pubkey)
        XCTAssertEqual(new.content, "")
        XCTAssertEqual(new.tags.count, 3)
        XCTAssertEqual(new.tags[0][0].string(), "d")
        XCTAssertEqual(new.tags[0][1].string(), "mute")
        XCTAssertEqual(new.tags[1][0].string(), "p")
        XCTAssertEqual(new.tags[1][1].string(), to_mute.hex())
        XCTAssertEqual(new.tags[2][0].string(), "p")
        XCTAssertEqual(new.tags[2][1].string(), to_mute_2.hex())
    }
}
