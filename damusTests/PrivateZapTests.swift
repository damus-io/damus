//
//  PrivateZapTests.swift
//  damusTests
//
//  Created by Claude on 2026-09-05.
//

import XCTest
@testable import damus

/// Covers ``ZapType/forced(on:requested:ndb:)`` — the rule that a zap at a note which came out of a
/// gift wrap is sent as a private zap whatever was asked for.
///
/// Zapping a private reply is the one action here that cannot be made *entirely* private, and the
/// tests say so out loud rather than asserting only the comfortable half. What a private zap hides is
/// the sender's identity and the comment, both encrypted into the request's `anon` tag and readable
/// only by the recipient. What nothing hides is the kind-9735 receipt: the recipient's LNURL server
/// publishes it, and it names the zapped note and the recipient. So zapping a private reply does put
/// the rumor's id on a relay — an id that resolves for nobody, attached to a pubkey that does.
///
/// That cost is taken knowingly: the alternative on the table was no zap at all, and an observer has
/// no way to tell an unresolvable id from any of the many notes they simply do not hold.
/// ``testTheReceiptStillNamesTheNoteAndTheRecipient()`` is where that is written down, so the next
/// reader finds the limitation stated rather than discovering it.
final class PrivateZapTests: XCTestCase {

    // MARK: The rule

    /// Every type that would publish something about the sender becomes ``ZapType/priv``.
    ///
    /// ``ZapType/pub`` signs the request with our own key and puts the comment in the clear;
    /// ``ZapType/anon`` hides the key but still publishes the comment. Both end up inside the receipt,
    /// so on a note only two people hold, a public zap tells an observer that *this* person is talking
    /// to the note's author — which is precisely what the wrap around the note was for.
    @MainActor
    func testAZapAtAPrivateReplyIsForcedPrivateWhateverWasAsked() async throws {
        let (state, reply, author) = try await privateReplyInADatabase()
        let target = ZapTarget.note(id: reply.id, author: author.pubkey)

        XCTAssertTrue(target.isPrivateNote(ndb: state.ndb), "fixture: the database says this is a rumor")

        for requested in [ZapType.pub, .anon, .priv] {
            XCTAssertEqual(ZapType.forced(on: target, requested: requested, ndb: state.ndb), .priv,
                           "a \(requested) zap at a rumor is sent privately")
        }
    }

    /// **Except ``ZapType/non_zap``**, which is left exactly as it is.
    ///
    /// The tempting rule — "a zap at a rumor is always private" — gets this one wrong, and gets it
    /// wrong in the direction that leaks. A non-zap is not a weaker private zap, it is a plain
    /// lightning payment: `fetch_zap_invoice` never hands the zap request to the callback for one, so
    /// no receipt is published and *nothing whatever* reaches a relay. Forcing it to `.priv` would
    /// take the only choice that publishes nothing and make it publish a receipt.
    @MainActor
    func testANonZapIsLeftAloneBecauseItPublishesNothingAtAll() async throws {
        let (state, reply, author) = try await privateReplyInADatabase()
        let target = ZapTarget.note(id: reply.id, author: author.pubkey)

        XCTAssertEqual(ZapType.forced(on: target, requested: .non_zap, ndb: state.ndb), .non_zap,
                       "the more private choice must not be replaced by the less private one")
    }

    /// The public app is untouched: a zap at an ordinary note is sent as whatever was asked for.
    @MainActor
    func testAZapAtAPublicNoteIsUnchanged() async throws {
        let state = make_test_damus_state()
        let bob = generate_new_keypair()
        let note = try XCTUnwrap(NostrEvent(content: "a public note", keypair: bob.to_keypair(), kind: 1, tags: []))
        try state.ndb.add(event: note)
        let target = ZapTarget.note(id: note.id, author: bob.pubkey)

        XCTAssertFalse(target.isPrivateNote(ndb: state.ndb))
        for requested in [ZapType.pub, .anon, .priv, .non_zap] {
            XCTAssertEqual(ZapType.forced(on: target, requested: requested, ndb: state.ndb), requested)
        }
    }

    /// A profile zap has no note to be private about, so nothing is forced — including when the
    /// profile is that of somebody we have a private conversation with.
    @MainActor
    func testAProfileZapIsUnchanged() async throws {
        let (state, _, author) = try await privateReplyInADatabase()
        let target = ZapTarget.profile(author.pubkey)

        XCTAssertFalse(target.isPrivateNote(ndb: state.ndb))
        XCTAssertEqual(ZapType.forced(on: target, requested: .pub, ndb: state.ndb), .pub)
    }

    /// A note we do not hold is one we cannot be displaying, and so cannot be zapping from the UI.
    /// Recorded because it is the rule's one soft edge: the answer comes from the database, and a
    /// database that has never seen the note has nothing to say about it.
    @MainActor
    func testANoteTheDatabaseDoesNotHoldIsNotTreatedAsPrivate() async throws {
        let state = make_test_damus_state()
        let bob = generate_new_keypair()
        let unseen = try XCTUnwrap(NostrEvent(content: "never ingested", keypair: bob.to_keypair(), kind: 1, tags: []))

        XCTAssertFalse(ZapTarget.note(id: unseen.id, author: bob.pubkey).isPrivateNote(ndb: state.ndb))
    }

    // MARK: What the forced zap actually publishes

    /// The half that works: with the forced type, the request that goes to the LNURL callback carries
    /// neither our pubkey nor our comment, and the recipient can recover both.
    @MainActor
    func testTheForcedZapHidesTheSenderAndTheCommentFromEveryoneElse() async throws {
        let (state, reply, them) = try await privateReplyInADatabase()
        let us = test_keypair_full
        let target = ZapTarget.note(id: reply.id, author: them.pubkey)

        let zap_type = ZapType.forced(on: target, requested: .pub, ndb: state.ndb)
        let made = try XCTUnwrap(make_zap_request_event(keypair: us, content: "nice one", relays: [],
                                                        target: target, zap_type: zap_type))
        let outer = made.potentially_anon_outer_request.ev

        XCTAssertNotEqual(outer.pubkey, us.pubkey, "the published request is signed by a derived key, not by us")
        XCTAssertEqual(outer.content, "", "and the comment is not in the clear")
        XCTAssertTrue(outer.tags.contains(where: { $0.count >= 2 && $0[0].string() == "anon" && !$0[1].string().isEmpty }),
                      "it is in the encrypted anon tag instead")

        // And the one person it is for can open it.
        let recovered = try XCTUnwrap(decrypt_private_zap(our_privkey: them.privkey, zapreq: outer, target: target))
        XCTAssertEqual(recovered.pubkey, us.pubkey, "the recipient learns who zapped them")
        XCTAssertEqual(recovered.content, "nice one", "and what they said")
    }

    /// **The half that does not work, stated deliberately.** The receipt the recipient's LNURL server
    /// publishes carries the request's `e` and `p` tags, so zapping a private reply announces that
    /// *some* note belonging to that pubkey was zapped — and that note is one nobody else has.
    ///
    /// This is not a bug to be fixed by a later commit. Removing the `e` tag would mean zapping the
    /// author rather than the note, which no client could attribute to the reply, so the zap would show
    /// on nobody's copy of it. The judgement made was that an opaque id an observer cannot distinguish
    /// from any unfetched note is a smaller cost than losing the affordance, and this test is where
    /// that judgement is recorded rather than rediscovered.
    @MainActor
    func testTheReceiptStillNamesTheNoteAndTheRecipient() async throws {
        let (state, reply, them) = try await privateReplyInADatabase()
        let target = ZapTarget.note(id: reply.id, author: them.pubkey)

        let zap_type = ZapType.forced(on: target, requested: .pub, ndb: state.ndb)
        let made = try XCTUnwrap(make_zap_request_event(keypair: test_keypair_full, content: "nice one",
                                                        relays: [], target: target, zap_type: zap_type))
        let outer = made.potentially_anon_outer_request.ev

        XCTAssertEqual(Array(outer.referenced_ids), [reply.id],
                       "the rumor's id is in the request, and so ends up in the public receipt")
        XCTAssertEqual(Array(outer.referenced_pubkeys), [them.pubkey],
                       "as does the recipient, which is what the LNURL server needs to publish one at all")
    }

    // MARK: Fixtures

    /// A real `DamusState` whose nostrdb holds a private reply **somebody else sent us**, read back
    /// with its rumor flag set by nostrdb's unwrapper — the only thing that sets it, and the only
    /// thing `isPrivateNote` trusts.
    ///
    /// Inbound rather than one of our own, because zapping is something you do to another person's
    /// note: the author is who the sats go to and whose key decrypts the private zap. Built by putting
    /// a real wrap through the real ingester rather than by hand, because a kind 1 inserted directly
    /// would carry no flag and every assertion here would be vacuous.
    ///
    /// - Returns: the state, the reply as we read it, and the full keypair of whoever wrote it.
    @MainActor
    private func privateReplyInADatabase() async throws -> (state: DamusState, reply: NostrEvent, author: FullKeypair) {
        let state = make_test_damus_state()
        XCTAssertTrue(state.ndb.add_key(test_keypair_full.privkey), "the ingester needs our key to unwrap")

        let bob = generate_new_keypair()
        let ourNote = try XCTUnwrap(NostrEvent(content: "our public note", keypair: test_keypair,
                                               kind: 1, tags: []))
        try state.ndb.add(event: ourNote)

        let post = NostrPost(content: "between us",
                             tags: nip10_reply_tags(replying_to: ourNote, keypair: bob.to_keypair(), relayURL: nil))
        let built = try NIP59.createPrivateReply(post, replyingTo: ourNote, keypair: bob)

        // The copy addressed to us, which is the one that would arrive off a relay.
        try state.ndb.add(event: try XCTUnwrap(built.giftWrapToReceiver))

        var found: NdbNote? = nil
        for _ in 0..<200 {
            found = try? state.ndb.lookup_note_and_copy(built.rumor.id)
            if found != nil { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let reply = try XCTUnwrap(found, "nostrdb never produced the rumor")
        XCTAssertTrue(reply.is_rumor, "fixture is only meaningful if nostrdb flagged it")
        XCTAssertEqual(reply.pubkey, bob.pubkey, "and that it is bob's, copied off the seal")

        return (state, reply, bob)
    }
}
