//
//  DMTests.swift
//  damusTests
//
//  Created by William Casarin on 2023-01-14.
//

import XCTest
@testable import damus

final class DMTests: XCTestCase {

    var alice: Keypair {
        let sec = hex_decode_privkey("494c680d20f202807a116a6915815bd76a27d62802e7585806f6a2e034cb5cdb")!
        let pk = hex_decode_pubkey("22d925632551a3299022e98de7f9c1087f79a21209f3413ec24ec219b08bd1e4")!
        return Keypair(pubkey: pk, privkey: sec)
    }
    
    var bob: Keypair {
        let sec = hex_decode_privkey("aa8920b05b4bd5c79fce46868ed5ebc82bdb91b211850b14541bfbd13953cfef")!
        let pk = hex_decode_pubkey("5a9a277dca94260688ecf7d63053de8c121b7f01f609d7f84a1eb9cff64e4606")!
        return Keypair(pubkey: pk, privkey: sec)
    }
    
    var charlie: Keypair {
        let sec = hex_decode_privkey("4c79130952c9c3b017dad62f37f285853a9c53f2a1184d94594f5b860f30b5a5")!
        let pk = hex_decode_pubkey("51c0d263fbfc4bf850805dccf9a29125071e6fed9619bff3efa9a6b5bbcc54a7")!
        return Keypair(pubkey: pk, privkey: sec)
    }
    
    var dave: Keypair {
        let sec = hex_decode_privkey("630ffd518084334cbb9ecb20d9532ce0658b8123f4ba565c236d0cea9a4a2cfe")!
        let pk = hex_decode_pubkey("b42e44b555013239a0d5dcdb09ebde0857cd8a5a57efbba5a2b6ac78833cb9f0")!
        return Keypair(pubkey: pk, privkey: sec)
    }
    
    var fiatjaf: Keypair {
        let sec = hex_decode_privkey("5426893eab32191ec17a83a583d5c8f85adaabcab0fa56af277ea0b61f575599")!
        let pub = hex_decode_pubkey("e27258d7be6d84038967334bfd0954f05801b1bcd85b2afa4c03cfd16ae4b0ad")!
        return Keypair(pubkey: pub, privkey: sec)
    }

/*
    func testDMSortOrder() throws {
        let notif = NewEventsBits()
        let pubkey = hex_decode_pubkey("3efdaebb1d8923ebd99c9e7ace3b4194ab45512e2be79c1b7d68d9243e0d2681")!
        let model = DirectMessagesModel(our_pubkey: pubkey)
        
        let now = UInt32(Date().timeIntervalSince1970)

        let alice_to_bob = create_dm("hi bob", to_pk: bob.pubkey, tags: [bob.pubkey.tag], keypair: alice, created_at: now)!
        handle_incoming_dms(prev_events: notif, dms: model, our_pubkey: alice.pubkey, evs: [alice_to_bob])
        
        XCTAssertEqual(model.dms.count, 1)
        XCTAssertEqual(model.dms[0].pubkey, bob.pubkey)

        let bob_to_alice = create_dm("hi alice", to_pk: alice.pubkey, tags: [alice.pubkey.tag], keypair: bob, created_at: now + 1)!
        handle_incoming_dms(prev_events: notif, dms: model, our_pubkey: alice.pubkey, evs: [bob_to_alice])
        
        XCTAssertEqual(model.dms.count, 1)
        XCTAssertEqual(model.dms[0].pubkey, bob.pubkey)
        
        let alice_to_bob_2 = create_dm("hi bob", to_pk: bob.pubkey, tags: [bob.pubkey.tag], keypair: alice, created_at: now + 2)!
        handle_incoming_dms(prev_events: notif, dms: model, our_pubkey: alice.pubkey, evs: [alice_to_bob_2])
        
        XCTAssertEqual(model.dms.count, 1)
        XCTAssertEqual(model.dms[0].pubkey, bob.pubkey)
        
        let fiatjaf_to_alice = create_dm("hi alice", to_pk: alice.pubkey, tags: [alice.pubkey.tag], keypair: fiatjaf, created_at: now+5)!
        handle_incoming_dms(prev_events: notif, dms: model, our_pubkey: alice.pubkey, evs: [fiatjaf_to_alice])
        
        XCTAssertEqual(model.dms.count, 2)
        XCTAssertEqual(model.dms[0].pubkey, fiatjaf.pubkey)
        
        let dave_to_alice = create_dm("hi alice", to_pk: alice.pubkey, tags: [alice.pubkey.tag], keypair: dave, created_at: now + 10)!
        handle_incoming_dms(prev_events: notif, dms: model, our_pubkey: alice.pubkey, evs: [dave_to_alice])

        XCTAssertEqual(model.dms.count, 3)
        XCTAssertEqual(model.dms[0].pubkey, dave.pubkey)

        let bob_to_alice_2 = create_dm("hi alice 2", to_pk: alice.pubkey, tags: [alice.pubkey.tag], keypair: bob, created_at: now + 15)!
        handle_incoming_dms(prev_events: notif, dms: model, our_pubkey: alice.pubkey, evs: [bob_to_alice_2])

        XCTAssertEqual(model.dms.count, 3)
        XCTAssertEqual(model.dms[0].pubkey, bob.pubkey)

        let charlie_to_alice = create_dm("hi alice", to_pk: alice.pubkey, tags: [alice.pubkey.tag], keypair: charlie, created_at: now + 20)!
        handle_incoming_dms(prev_events: notif, dms: model, our_pubkey: alice.pubkey, evs: [charlie_to_alice])

        XCTAssertEqual(model.dms.count, 4)
        XCTAssertEqual(model.dms[0].pubkey, charlie.pubkey)

        let bob_to_alice_3 = create_dm("hi alice 3", to_pk: alice.pubkey, tags: [alice.pubkey.tag], keypair: bob, created_at: now + 25)!
        handle_incoming_dms(prev_events: notif, dms: model, our_pubkey: alice.pubkey, evs: [bob_to_alice_3])

        XCTAssertEqual(model.dms.count, 4)
        XCTAssertEqual(model.dms[0].pubkey, bob.pubkey)

        let charlie_to_alice_2 = create_dm("hi alice 2", to_pk: alice.pubkey, tags: [alice.pubkey.tag], keypair: charlie, created_at: now + 30)!
        handle_incoming_dms(prev_events: notif, dms: model, our_pubkey: alice.pubkey, evs: [charlie_to_alice_2])

        XCTAssertEqual(model.dms.count, 4)
        XCTAssertEqual(model.dms[0].pubkey, charlie.pubkey)
    }
 */

    // MARK: - NIP-17 kind-14 conversation keying

    /// Builds a kind-14 note shaped like the rumors nostrdb hands us after peeling a giftwrap:
    /// plaintext content, the sender as author, and one `p` tag per receiver.
    ///
    /// A real rumor is unsigned; this one is signed, because the only way to build a note in a test
    /// is to sign it. That difference does not reach the functions under test — the rumor flag is
    /// checked one level up, in `HomeModel.handle_private_dm`, which needs a live `DamusState` and a
    /// nostrdb that actually unwrapped something.
    private func rumor(_ content: String, from: Keypair, to: [Pubkey], created_at: UInt32) -> NostrEvent {
        return NostrEvent(
            content: content,
            keypair: from,
            kind: NostrKind.private_dm.rawValue,
            tags: to.map({ $0.tag }),
            createdAt: created_at
        )!
    }

    func testInboundRumorIsKeyedOnItsSender() throws {
        let ev = rumor("hi alice", from: bob, to: [alice.pubkey], created_at: 1000)
        XCTAssertEqual(nip17_conversation_pubkey(rumor: ev, our_pubkey: alice.pubkey), bob.pubkey)
    }

    func testOutboundRumorIsKeyedOnItsRecipient() throws {
        // The rumor inside the giftwrap we address to ourselves on send: we are the author, and the
        // counterparty is only in the `p` tag.
        let ev = rumor("hi bob", from: alice, to: [bob.pubkey], created_at: 1000)
        XCTAssertEqual(nip17_conversation_pubkey(rumor: ev, our_pubkey: alice.pubkey), bob.pubkey)
    }

    func testRumorTaggingBothPartiesIsStillOneToOne() throws {
        // Some clients tag the sender alongside the receiver. Two `p` tags, but still two people.
        let ev = rumor("hi alice", from: bob, to: [alice.pubkey, bob.pubkey], created_at: 1000)
        XCTAssertEqual(nip17_conversation_pubkey(rumor: ev, our_pubkey: alice.pubkey), bob.pubkey)
    }

    func testNoteToSelfIsKeyedOnUs() throws {
        let ev = rumor("remember the milk", from: alice, to: [alice.pubkey], created_at: 1000)
        XCTAssertEqual(nip17_conversation_pubkey(rumor: ev, our_pubkey: alice.pubkey), alice.pubkey)
    }

    /// A group chat has no home in the DM list, so it must not land in one.
    func testGroupRumorIsDropped() throws {
        let ev = rumor("hi both", from: bob, to: [alice.pubkey, charlie.pubkey], created_at: 1000)
        XCTAssertNil(nip17_conversation_pubkey(rumor: ev, our_pubkey: alice.pubkey))

        let notif = NewEventsBits()
        let model = DirectMessagesModel(our_pubkey: alice.pubkey)
        handle_incoming_dms(prev_events: notif, dms: model, our_pubkey: alice.pubkey, evs: [ev])

        // Specifically: no conversation with bob, and no conversation with charlie either.
        XCTAssertEqual(model.dms.count, 0)
    }

    func testRumorWeAreNotAPartyToIsDropped() throws {
        let ev = rumor("hi charlie", from: bob, to: [charlie.pubkey], created_at: 1000)
        XCTAssertNil(nip17_conversation_pubkey(rumor: ev, our_pubkey: alice.pubkey))
    }

    func testRumorsBuildBothDirectionsOfOneConversation() throws {
        let notif = NewEventsBits()
        let model = DirectMessagesModel(our_pubkey: alice.pubkey)

        let inbound = rumor("hi alice", from: bob, to: [alice.pubkey], created_at: 1000)
        let outbound = rumor("hi bob", from: alice, to: [bob.pubkey], created_at: 1001)
        handle_incoming_dms(prev_events: notif, dms: model, our_pubkey: alice.pubkey, evs: [inbound, outbound])

        XCTAssertEqual(model.dms.count, 1)
        XCTAssertEqual(model.dms[0].pubkey, bob.pubkey)
        XCTAssertEqual(model.dms[0].events.map({ $0.content }), ["hi alice", "hi bob"])
        // Alice has replied, so this is a conversation rather than a message request.
        XCTAssertFalse(model.dms[0].is_request)
    }

    /// Conversations are ordered by the rumor's own `created_at`, which is the real send time. The
    /// giftwrap's randomized timestamp never reaches this model, and this is the ordering that would
    /// be wrong if it ever did.
    func testConversationsAreOrderedByRumorCreatedAt() throws {
        let notif = NewEventsBits()
        let model = DirectMessagesModel(our_pubkey: alice.pubkey)

        let from_bob = rumor("hi alice", from: bob, to: [alice.pubkey], created_at: 1000)
        let from_charlie = rumor("hey alice", from: charlie, to: [alice.pubkey], created_at: 2000)
        let from_dave = rumor("yo alice", from: dave, to: [alice.pubkey], created_at: 1500)

        handle_incoming_dms(prev_events: notif, dms: model, our_pubkey: alice.pubkey, evs: [from_bob, from_charlie, from_dave])

        XCTAssertEqual(model.dms.map({ $0.pubkey }), [charlie.pubkey, dave.pubkey, bob.pubkey])
    }

    /// Legacy kind-4 DMs keep their own keying, which the shared insert path must not have changed.
    func testLegacyDmKeyingIsUnchanged() throws {
        let inbound = NostrEvent(content: "encrypted", keypair: bob, kind: NostrKind.dm.rawValue, tags: [alice.pubkey.tag], createdAt: 1000)!

        let notif = NewEventsBits()
        let model = DirectMessagesModel(our_pubkey: alice.pubkey)
        handle_incoming_dms(prev_events: notif, dms: model, our_pubkey: alice.pubkey, evs: [inbound])

        XCTAssertEqual(model.dms.count, 1)
        XCTAssertEqual(model.dms[0].pubkey, bob.pubkey)
    }
}
