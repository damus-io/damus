//
//  PrivateReplyRoundTripTests.swift
//  damusTests
//
//  Created by Claude on 2026-09-05.
//

import XCTest
@testable import damus

/// The end-to-end round trip, and the negative assertions that are the actual point of the feature.
///
/// The round trip is the easy half: build a private reply, publish it, read it back, and check both
/// parties see the same message. The negatives are the half worth having. Each one is a leak if it
/// regresses, and most of them are the kind a refactor reintroduces silently — nothing crashes, no
/// test times out, a message just quietly goes somewhere it should not.
///
/// Several of the card's assertions are already made elsewhere and are not duplicated here:
/// `PrivateReplyTests` covers the two wraps being unlinkable, the self-reply emitting one wrap, and
/// no wrap carrying the plaintext; `PrivateReplyIngestTests` covers a signed kind 1 never being a
/// private reply however it is tagged; `DraftTests` covers a draft round-tripping with its privacy
/// intact; `PrivateReplyChainTests` covers the pubkey-only login at the composer and the action bar.
/// The builder's pubkey-only case needs no test: it takes a `FullKeypair` non-optionally, so a
/// pubkey-only login cannot reach it at all, and the compiler is a better assertion than a test.
final class PrivateReplyRoundTripTests: XCTestCase {

    // MARK: The round trip, both sides of one message

    /// One built reply, read back by both parties out of two separate databases, and cross-checked.
    ///
    /// Both halves exist separately in `PrivateReplyIngestTests`; the point of doing them together is
    /// the cross-check at the end. The sender and the recipient hold different wraps, sealed to
    /// different keys with different ephemeral keys, and the only thing that makes it *one*
    /// conversation is that the rumor inside is identical. That is not implied by either half on its
    /// own.
    func testBothPartiesReadTheSameReplyOutOfTheirOwnWrap() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let parent = try XCTUnwrap(NostrEvent(content: "bob's public note", keypair: bob.to_keypair(),
                                              kind: NostrKind.text.rawValue, tags: []))
        let tags = nip10_reply_tags(replying_to: parent, keypair: alice.to_keypair(), relayURL: nil)
        let built = try NIP59.createPrivateReply(NostrPost(content: "just between us", tags: tags),
                                                 replyingTo: parent, keypair: alice)

        let ours = try unwrap(built.giftWrapToSelf, with: alice)
        let theirs = try unwrap(try XCTUnwrap(built.giftWrapToReceiver), with: bob)

        for (who, rumor) in [("sender", ours), ("recipient", theirs)] {
            XCTAssertEqual(rumor.kind, 1, "\(who): an ordinary kind 1")
            XCTAssertTrue(rumor.is_rumor, "\(who): flagged by nostrdb's unwrapper")
            XCTAssertTrue(rumor.is_private_reply, "\(who)")
            XCTAssertEqual(rumor.content, "just between us", "\(who)")
            XCTAssertEqual(rumor.pubkey, alice.pubkey, "\(who): the sender pubkey copied off the seal")
            XCTAssertEqual(rumor.thread_reply()?.reply.note_id, parent.id, "\(who): the same parent")
        }

        XCTAssertEqual(ours.id, theirs.id,
                       "the same rumor, so it is one message and not two — despite two wraps, two seals and two ephemeral keys")
        XCTAssertEqual(ours.created_at, theirs.created_at, "and one send time, which is what the thread orders by")
        XCTAssertEqual(ours.rumor_receiver_pubkey, alice.pubkey)
        XCTAssertEqual(theirs.rumor_receiver_pubkey, bob.pubkey,
                       "each copy knows whose key opened it, which is what tells the two apart")
    }

    /// And it lands in the thread on the recipient's side, which is the whole reason it carries NIP-10
    /// tags instead of being a DM.
    @MainActor
    func testTheRecipientFindsItInTheThreadForTheParent() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let parent = try XCTUnwrap(NostrEvent(content: "bob's public note", keypair: bob.to_keypair(),
                                              kind: NostrKind.text.rawValue, tags: []))
        let tags = nip10_reply_tags(replying_to: parent, keypair: alice.to_keypair(), relayURL: nil)
        let built = try NIP59.createPrivateReply(NostrPost(content: "answering you", tags: tags),
                                                 replyingTo: parent, keypair: alice)
        let rumor = try unwrap(try XCTUnwrap(built.giftWrapToReceiver), with: bob)

        let state = make_test_damus_state(keypair: bob.to_keypair())
        let thread = ThreadModel(event: parent, damus_state: state)
        thread.add_event(rumor, keypair: state.keypair)

        XCTAssertTrue(thread.sorted_child_events.contains(where: { $0.id == rumor.id }))
    }

    // MARK: Nothing but wraps, across a whole send

    /// Everything `PostBox` was handed across a real send, inspected as JSON.
    ///
    /// `PrivateReplySendTests` asserts the shape of what is queued — two events, both kind 1059. This
    /// asserts the stronger thing, which is that the plaintext, the rumor's id and our own pubkey
    /// appear in *no outbound frame at all*, wrap contents included. A wrap whose encryption silently
    /// stopped happening would still pass a kind check.
    @MainActor
    func testNoOutboundFrameContainsThePlaintextTheRumorIdOrUs() async throws {
        let state = make_test_damus_state()
        XCTAssertTrue(state.ndb.add_key(test_keypair_full.privkey))
        let bob = generate_new_keypair()
        let parent = try XCTUnwrap(NostrEvent(content: "a public note", keypair: bob.to_keypair(), kind: 1, tags: []))
        try state.ndb.add(event: parent)

        let secret = "correcthorsebatterystaple"
        let post = NostrPost(content: secret,
                             tags: nip10_reply_tags(replying_to: parent, keypair: test_keypair, relayURL: nil))
        let built = try NIP59.createPrivateReply(post, replyingTo: parent, keypair: test_keypair_full)

        let sent = await send_private_reply(post, replyingTo: parent, keypair: test_keypair_full, damus_state: state)
        XCTAssertTrue(sent)

        let queued = await state.nostrNetwork.postbox.events
        XCTAssertEqual(queued.count, 2, "one wrap per addressee, and nothing else")

        for posted in queued.values {
            let json = try XCTUnwrap(encode_json(posted.event))
            XCTAssertEqual(posted.event.kind, 1059)
            XCTAssertFalse(json.contains(secret),
                           "the message must not appear in an outbound frame, in the content or anywhere else")
            XCTAssertNotEqual(posted.event.pubkey, state.pubkey, "our own key must never sign a wrap")
            XCTAssertNotEqual(posted.event.id, built.rumor.id)
        }

        // Our pubkey does appear in exactly one frame — the `p` tag on the copy addressed to us,
        // which is how a relay routes it to our own inbox. It must not appear in the *other* one:
        // a wrap to bob that also named us would tie the two wraps together and identify the sender,
        // which is the correlation the ephemeral key exists to prevent.
        let theirs = try XCTUnwrap(queued.values.first(where: { $0.event.referenced_pubkeys.first != state.pubkey }))
        XCTAssertFalse(try XCTUnwrap(encode_json(theirs.event)).contains(state.pubkey.hex()),
                       "the recipient's wrap says nothing about who sent it")

        XCTAssertFalse(queued.keys.contains(built.rumor.id), "the rumor itself is never queued")
        XCTAssertFalse(queued.keys.contains(parent.id), "and the parent is not republished beside the wraps")
    }

    // MARK: The public path, unchanged

    /// A public reply still produces exactly the signed kind 1 it produced before this feature
    /// existed.
    ///
    /// Easy to break while adding a mode to the composer, and it would be caught in review rather
    /// than by a test unless one exists. The specific hazard is the `p` tags: the private path strips
    /// them and puts back a single one naming the audience, and doing that a layer too low would
    /// silently drop every mention from every public reply in the app.
    @MainActor
    func testAPublicReplyIsUnchangedByTheExistenceOfThePrivateOne() async throws {
        let state = make_test_damus_state()
        let bob = generate_new_keypair()
        let carol = generate_new_keypair()
        let parent = try XCTUnwrap(NostrEvent(content: "bob's note", keypair: bob.to_keypair(),
                                              kind: 1, tags: [["p", carol.pubkey.hex()]]))

        // The pubkeys the composer gathers for a reply: the parent's author and the other people
        // already in the thread. Passing them is what makes this the real path rather than a
        // degenerate one with no mention list to lose.
        let post = await build_post(state: state, post: NSMutableAttributedString(string: "a public answer"),
                                    action: .replying_to(parent), uploadedMedias: [],
                                    pubkeys: [bob.pubkey, carol.pubkey])
        let signed = try XCTUnwrap(post.to_event(keypair: test_keypair_full))

        XCTAssertEqual(signed.kind, 1)
        XCTAssertTrue(signed.verify(), "still signed by us, which is what makes it public")
        XCTAssertFalse(signed.is_rumor)
        XCTAssertFalse(signed.is_private_reply, "and so it draws no lock and keeps every action")
        XCTAssertEqual(NoteActions.available(on: signed, keypair: test_keypair), .all)

        // The tags the signing path writes are exactly the ones the shared renderer produced. That
        // split is phase 1's — `rendered()` was factored out of `to_event` so a private reply's reply
        // tags are byte-identical to the public reply it could have been — and this is the assertion
        // that the public half of it did not drift.
        XCTAssertEqual(signed.tags.map({ $0.strings() }), post.rendered().tags,
                       "signing adds a signature, not tags")

        // Every `p` tag the public path would have carried is still there. The private path is the
        // only thing that may replace them.
        let mentioned = Set(signed.tags.filter({ $0.count >= 2 && $0[0].string() == "p" }).map({ $0[1].string() }))
        XCTAssertTrue(mentioned.contains(bob.pubkey.hex()), "the parent's author")
        XCTAssertTrue(mentioned.contains(carol.pubkey.hex()), "and the other thread participant")
    }

    /// The same draft sent both ways, side by side: identical reply tags, and a different audience.
    ///
    /// This is the claim phase 1 was built around, stated once at the level a reader can check — that
    /// a private reply is the public reply it could have been, plus a wrap, minus the mention list.
    func testThePrivateReplyIsThePublicOneWithADifferentAudience() throws {
        let alice = test_keypair_full
        let bob = generate_new_keypair()
        let carol = generate_new_keypair()
        let parent = try XCTUnwrap(NostrEvent(content: "bob's note", keypair: bob.to_keypair(), kind: 1, tags: []))

        var tags = nip10_reply_tags(replying_to: parent, keypair: alice.to_keypair(), relayURL: nil)
        tags.append(["p", carol.pubkey.hex()])
        let post = NostrPost(content: "the same words", tags: tags)

        let publicReply = try XCTUnwrap(post.to_event(keypair: alice))
        let privateReply = try NIP59.createPrivateReply(post, replyingTo: parent, keypair: alice)

        let e_tags = { (tags: [[String]]) in tags.filter({ $0.first == "e" }) }
        XCTAssertEqual(e_tags(privateReply.rumor.tags),
                       e_tags(publicReply.tags.map({ $0.strings() })),
                       "identical reply tags, so it parses into exactly the same place in the thread")
        XCTAssertEqual(privateReply.rumor.content, publicReply.content)

        XCTAssertEqual(privateReply.rumor.tags.filter({ $0.first == "p" }), [["p", bob.pubkey.hex()]],
                       "one p tag, because on a rumor the p tags are the audience and not a mention list")
        XCTAssertTrue(publicReply.referenced_pubkeys.contains(carol.pubkey),
                      "while the public one still mentions carol")
    }

    // MARK: Helpers

    /// Puts `wrap` through a real nostrdb with `reader`'s key registered and returns the rumor.
    private func unwrap(_ wrap: NostrEvent, with reader: FullKeypair) throws -> NostrEvent {
        let dir = try XCTUnwrap(test_ndb_dir(), "could not create a temp directory")
        let wire = try "[\"EVENT\",\"s\",\(XCTUnwrap(encode_json(wrap)))]\n"
        do {
            let seed = try XCTUnwrap(Ndb(path: dir))
            XCTAssertTrue(seed.add_key(reader.privkey))
            XCTAssertTrue(seed.process_events(wire))
            seed.close()   // draining the ingester pool is what makes the unwrap deterministic
        }
        let ndb = try XCTUnwrap(Ndb(path: dir))
        defer { ndb.close() }

        let filter = try NdbFilter(from: NostrFilter(kinds: [.text]))
        let key = try XCTUnwrap(try ndb.query(filters: [filter], maxResults: 10).first)
        return try XCTUnwrap(try ndb.lookup_note_by_key_and_copy(key))
    }
}
