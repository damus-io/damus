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
        let privkey = "87f313b03f2548e6eaf1c188db47078e08e894252949779b639b28db0891937a"
        let pubkey = "4b0c29bf96496130c1253102f6870c0eee05db38a257315858272aa43fd19685"
        let to_mute = "2fa2630fea3d2c188c49f2799fcd92f0e9879ea6a36ae60770a5428ed6c19edd"
        let keypair = FullKeypair(pubkey: pubkey, privkey: privkey)
        let mutelist = create_or_update_mutelist(keypair: keypair, mprev: nil, to_add: to_mute)!
        
        XCTAssertEqual(mutelist.pubkey, pubkey)
        XCTAssertEqual(mutelist.content, "")
        XCTAssertEqual(mutelist.tags.count, 2)
        XCTAssertEqual(mutelist.tags[0][0], "d")
        XCTAssertEqual(mutelist.tags[0][1], "mute")
        XCTAssertEqual(mutelist.tags[1][0], "p")
        XCTAssertEqual(mutelist.tags[1][1], to_mute)
    }

    func testCreateAndRemoveMuteList() throws {
        let privkey = "87f313b03f2548e6eaf1c188db47078e08e894252949779b639b28db0891937a"
        let pubkey = "4b0c29bf96496130c1253102f6870c0eee05db38a257315858272aa43fd19685"
        let to_mute = "2fa2630fea3d2c188c49f2799fcd92f0e9879ea6a36ae60770a5428ed6c19edd"
        let keypair = FullKeypair(pubkey: pubkey, privkey: privkey)
        let mutelist = create_or_update_mutelist(keypair: keypair, mprev: nil, to_add: to_mute)!
        let new = remove_from_mutelist(keypair: keypair, prev: mutelist, to_remove: to_mute)!
        
        XCTAssertEqual(new.pubkey, pubkey)
        XCTAssertEqual(new.content, "")
        XCTAssertEqual(new.tags.count, 1)
        XCTAssertEqual(new.tags[0][0], "d")
        XCTAssertEqual(new.tags[0][1], "mute")
    }
    
    func testAddToExistingMutelist() throws {
        let privkey = "87f313b03f2548e6eaf1c188db47078e08e894252949779b639b28db0891937a"
        let pubkey = "4b0c29bf96496130c1253102f6870c0eee05db38a257315858272aa43fd19685"
        let to_mute = "2fa2630fea3d2c188c49f2799fcd92f0e9879ea6a36ae60770a5428ed6c19edd"
        let to_mute_2 = "976b4ab41f8634119b4f21f57ef5836a4bef65d0bf72c7ced67b8b170ba4a38d"
        let keypair = FullKeypair(pubkey: pubkey, privkey: privkey)
        let mutelist = create_or_update_mutelist(keypair: keypair, mprev: nil, to_add: to_mute)!
        let new = create_or_update_mutelist(keypair: keypair, mprev: mutelist, to_add: to_mute_2)!
        
        XCTAssertEqual(new.pubkey, pubkey)
        XCTAssertEqual(new.content, "")
        XCTAssertEqual(new.tags.count, 3)
        XCTAssertEqual(new.tags[0][0], "d")
        XCTAssertEqual(new.tags[0][1], "mute")
        XCTAssertEqual(new.tags[1][0], "p")
        XCTAssertEqual(new.tags[1][1], to_mute)
        XCTAssertEqual(new.tags[2][0], "p")
        XCTAssertEqual(new.tags[2][1], to_mute_2)
    }
}
