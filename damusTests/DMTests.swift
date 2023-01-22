//
//  DMTests.swift
//  damusTests
//
//  Created by William Casarin on 2023-01-14.
//

import XCTest
@testable import damus

final class DMTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }
    
    var alice: Keypair {
        let sec = "494c680d20f202807a116a6915815bd76a27d62802e7585806f6a2e034cb5cdb"
        let pk  = "22d925632551a3299022e98de7f9c1087f79a21209f3413ec24ec219b08bd1e4"
        return Keypair(pubkey: pk, privkey: sec)
    }
    
    var bob: Keypair {
        let sec = "aa8920b05b4bd5c79fce46868ed5ebc82bdb91b211850b14541bfbd13953cfef"
        let pk = "5a9a277dca94260688ecf7d63053de8c121b7f01f609d7f84a1eb9cff64e4606"
        return Keypair(pubkey: pk, privkey: sec)
    }
    
    var charlie: Keypair {
        let sec = "4c79130952c9c3b017dad62f37f285853a9c53f2a1184d94594f5b860f30b5a5"
        let pk = "51c0d263fbfc4bf850805dccf9a29125071e6fed9619bff3efa9a6b5bbcc54a7"
        return Keypair(pubkey: pk, privkey: sec)
    }
    
    var dave: Keypair {
        let sec = "630ffd518084334cbb9ecb20d9532ce0658b8123f4ba565c236d0cea9a4a2cfe"
        let pk = "b42e44b555013239a0d5dcdb09ebde0857cd8a5a57efbba5a2b6ac78833cb9f0"
        return Keypair(pubkey: pk, privkey: sec)
    }
    
    var fiatjaf: Keypair {
        let sec = "5426893eab32191ec17a83a583d5c8f85adaabcab0fa56af277ea0b61f575599"
        let pub = "e27258d7be6d84038967334bfd0954f05801b1bcd85b2afa4c03cfd16ae4b0ad"
        return Keypair(pubkey: pub, privkey: sec)
    }
    
    func testDMSortOrder() throws {
        let notif = NewEventsBits()
        let pubkey = "3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681"
        let model = DirectMessagesModel(our_pubkey: pubkey)
        
        let now = Int64(Date().timeIntervalSince1970)
        
        let alice_to_bob = create_dm("hi bob", to_pk: bob.pubkey, tags: [["p", bob.pubkey]], keypair: alice, created_at: now)!
        let _ = handle_incoming_dm(prev_events: notif, dms: model, our_pubkey: alice.pubkey, ev: alice_to_bob)
        
        XCTAssertEqual(model.dms.count, 1)
        XCTAssertEqual(model.dms[0].0, bob.pubkey)

        let bob_to_alice = create_dm("hi alice", to_pk: alice.pubkey, tags: [["p", alice.pubkey]], keypair: bob, created_at: now + 1)!
        let _ = handle_incoming_dm(prev_events: notif, dms: model, our_pubkey: alice.pubkey, ev: bob_to_alice)
        
        XCTAssertEqual(model.dms.count, 1)
        XCTAssertEqual(model.dms[0].0, bob.pubkey)
        
        let alice_to_bob_2 = create_dm("hi bob", to_pk: bob.pubkey, tags: [["p", bob.pubkey]], keypair: alice, created_at: now + 2)!
        let _ = handle_incoming_dm(prev_events: notif, dms: model, our_pubkey: alice.pubkey, ev: alice_to_bob_2)
        
        XCTAssertEqual(model.dms.count, 1)
        XCTAssertEqual(model.dms[0].0, bob.pubkey)
        
        let fiatjaf_to_alice = create_dm("hi alice", to_pk: alice.pubkey, tags: [["p", alice.pubkey]], keypair: fiatjaf, created_at: now+5)!
        let _ = handle_incoming_dm(prev_events: notif, dms: model, our_pubkey: alice.pubkey, ev: fiatjaf_to_alice)
        
        XCTAssertEqual(model.dms.count, 2)
        XCTAssertEqual(model.dms[0].0, fiatjaf.pubkey)
        
        let dave_to_alice = create_dm("hi alice", to_pk: alice.pubkey, tags: [["p", alice.pubkey]], keypair: dave, created_at: now + 10)!
        let _ = handle_incoming_dm(prev_events: notif, dms: model, our_pubkey: alice.pubkey, ev: dave_to_alice)
        
        XCTAssertEqual(model.dms.count, 3)
        XCTAssertEqual(model.dms[0].0, dave.pubkey)
        
        let bob_to_alice_2 = create_dm("hi alice 2", to_pk: alice.pubkey, tags: [["p", alice.pubkey]], keypair: bob, created_at: now + 15)!
        let _ = handle_incoming_dm(prev_events: notif, dms: model, our_pubkey: alice.pubkey, ev: bob_to_alice_2)
        
        XCTAssertEqual(model.dms.count, 3)
        XCTAssertEqual(model.dms[0].0, bob.pubkey)
        
        let charlie_to_alice = create_dm("hi alice", to_pk: alice.pubkey, tags: [["p", alice.pubkey]], keypair: charlie, created_at: now + 20)!
        let _ = handle_incoming_dm(prev_events: notif, dms: model, our_pubkey: alice.pubkey, ev: charlie_to_alice)
        
        XCTAssertEqual(model.dms.count, 4)
        XCTAssertEqual(model.dms[0].0, charlie.pubkey)
        
        let bob_to_alice_3 = create_dm("hi alice 3", to_pk: alice.pubkey, tags: [["p", alice.pubkey]], keypair: bob, created_at: now + 25)!
        let _ = handle_incoming_dm(prev_events: notif, dms: model, our_pubkey: alice.pubkey, ev: bob_to_alice_3)
        
        XCTAssertEqual(model.dms.count, 4)
        XCTAssertEqual(model.dms[0].0, bob.pubkey)
        
        let charlie_to_alice_2 = create_dm("hi alice 2", to_pk: alice.pubkey, tags: [["p", alice.pubkey]], keypair: charlie, created_at: now + 30)!
        let _ = handle_incoming_dm(prev_events: notif, dms: model, our_pubkey: alice.pubkey, ev: charlie_to_alice_2)
        
        XCTAssertEqual(model.dms.count, 4)
        XCTAssertEqual(model.dms[0].0, charlie.pubkey)
        
        
        //let alice_to_bob_2 = create_dm("whats up", to_pk: bob.pubkey, tags: [], keypair: alice, created_at: now + 6)
        
        //let charlie_to_alice = create_dm("hi alice", to_pk: alice.pubkey, tags: [], keypair: charlie, created_at: now + 7)
        //let alice_to_charlie = create_dm("hey charlie", to_pk: charlie.pubkey, tags[], keypair: alice, created_at: now + 8)
        
        //handle_incoming_dm(prev_events: notif, dms: model, our_pubkey: pk, ev: ev)
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        self.measure {
            // Put the code you want to measure the time of here.
        }
    }

}
