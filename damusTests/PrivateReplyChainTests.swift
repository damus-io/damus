//
//  PrivateReplyChainTests.swift
//  damusTests
//
//  Created by Claude on 2026-09-05.
//

import XCTest
@testable import damus

/// Covers what happens when the note being replied to is *itself* a private reply: the composer's
/// lock is on and is not a choice, and the reply goes to the one person on the other end of that
/// conversation.
///
/// The failure this guards against is the sharpest one in the feature. The parent is a rumor whose
/// content two people have; a public reply to it would carry an `e` tag to an id nobody else can
/// resolve and, in practice, the user paraphrasing what they just read to an audience of everyone.
///
/// So these drive the composer — `PostView`'s own state — rather than the builder. The builder
/// cannot make a public reply at all; only the composer can, which makes the composer the thing that
/// has to be tested.
final class PrivateReplyChainTests: XCTestCase {

    // MARK: The composer

    /// The lock is on the moment the composer opens, with the toggle in its default *off* position —
    /// which is the point: what decides is the note being answered, not the switch.
    @MainActor
    func testReplyingToAPrivateReplyOpensLocked() throws {
        let alice = test_keypair_full
        let bob = generate_new_keypair()
        let parent = try privateReply(from: bob, toANoteBy: alice, read: alice)

        let composer = PostView(action: .replying_to(parent), damus_state: make_test_damus_state())

        XCTAssertFalse(composer.is_private_reply, "the toggle is in its default position")
        XCTAssertTrue(composer.private_reply_required)
        XCTAssertTrue(composer.sending_privately, "and the reply is private anyway")
    }

    /// Turning the toggle off does not make the reply public. `sending_privately` is the value the
    /// send path and the button label read, and it ignores the toggle when the parent is private —
    /// which is why `PrivacyButton` renders as a locked, untappable icon in that case, instead of as
    /// a toggle that snaps back.
    @MainActor
    func testTheLockCannotBeTurnedOff() throws {
        let alice = test_keypair_full
        let bob = generate_new_keypair()
        let parent = try privateReply(from: bob, toANoteBy: alice, read: alice)

        var composer = PostView(action: .replying_to(parent), damus_state: make_test_damus_state())
        composer.is_private_reply = false

        XCTAssertTrue(composer.sending_privately)
    }

    /// An ordinary public parent is unaffected: the lock is offered and starts off.
    @MainActor
    func testReplyingToAPublicNoteIsUnchanged() throws {
        let bob = generate_new_keypair()
        let parent = try XCTUnwrap(NostrEvent(content: "bob says something", keypair: bob.to_keypair(), kind: 1, tags: []))

        let composer = PostView(action: .replying_to(parent), damus_state: make_test_damus_state())

        XCTAssertFalse(composer.private_reply_required)
        XCTAssertTrue(composer.can_reply_privately, "the lock is still offered")
        XCTAssertFalse(composer.sending_privately, "it is just not forced")
    }

    /// **The natural wrong assumption, written down.** A reply does not inherit privacy from its
    /// thread — only from the note it directly answers. A public note sitting under a private
    /// ancestor is replied to publicly, because the note being answered is already public and
    /// answering it privately would be a promise about an exchange that is not private.
    ///
    /// Our own client cannot produce such a note (the reply affordance on a private reply always
    /// yields a private reply), but another client can, by publicly replying to a rumor id.
    @MainActor
    func testAPublicNoteUnderAPrivateAncestorRepliesPublicly() throws {
        let alice = test_keypair_full
        let bob = generate_new_keypair()
        let privateAncestor = try privateReply(from: bob, toANoteBy: alice, read: alice)

        // What another client would publish: a signed kind 1 whose reply tag names the rumor.
        let publicChild = try XCTUnwrap(NostrEvent(
            content: "some other client replied to a rumor in the clear",
            keypair: bob.to_keypair(),
            kind: 1,
            tags: [["e", privateAncestor.id.hex(), "", "reply"], ["p", alice.pubkey.hex()]]
        ))
        XCTAssertFalse(publicChild.is_private_reply, "it is signed, so it is public whatever it points at")

        let composer = PostView(action: .replying_to(publicChild), damus_state: make_test_damus_state())

        XCTAssertFalse(composer.private_reply_required, "privacy belongs to a message, not to a thread")
        XCTAssertFalse(composer.sending_privately)
    }

    // MARK: The audience

    /// Replying to a private reply somebody sent us goes back to them, by the plain
    /// parent-author rule.
    @MainActor
    func testTheAudienceIsTheSenderOfTheReplyWeReceived() throws {
        let alice = test_keypair_full
        let bob = generate_new_keypair()
        let parent = try privateReply(from: bob, toANoteBy: alice, read: alice)

        let composer = PostView(action: .replying_to(parent), damus_state: make_test_damus_state())

        XCTAssertEqual(composer.private_reply_recipient, bob.pubkey)
        XCTAssertEqual(NIP59.privateReplyAudience(replyingTo: parent, as: alice.pubkey), bob.pubkey)
    }

    /// Replying to a private reply of **our own** — which the thread shows us, and which has a reply
    /// button like any other note — continues the conversation with the person it was addressed to.
    ///
    /// The parent-author rule taken literally would address it to ourselves, since we wrote the
    /// parent. That is a note only we can ever read, in a sub-thread the other person never sees
    /// continue: the user believes they have answered and they have not. So the rule is the parent's
    /// *counterparty*, which is the same thing in every other case.
    @MainActor
    func testReplyingToOurOwnPrivateReplyStaysWithTheCounterparty() throws {
        let alice = test_keypair_full
        let bob = generate_new_keypair()
        let ours = try privateReply(from: alice, toANoteBy: bob, read: alice)
        XCTAssertEqual(ours.pubkey, alice.pubkey, "the parent is ours")

        XCTAssertEqual(NIP59.privateReplyAudience(replyingTo: ours, as: alice.pubkey), bob.pubkey,
                       "not ourselves — the conversation is with bob")

        let composer = PostView(action: .replying_to(ours), damus_state: make_test_damus_state())
        XCTAssertEqual(composer.private_reply_recipient, bob.pubkey,
                       "and the lock row names bob, so the composer says where it is really going")
    }

    /// End to end: the reply the builder makes from a private parent is a rumor answering *that*
    /// rumor and addressed to the one counterparty — never widening, never re-tagging the thread's
    /// other participants.
    func testAReplyToAPrivateReplyAnswersTheRumorAndAddsNobody() throws {
        let alice = test_keypair_full
        let bob = generate_new_keypair()
        let carol = generate_new_keypair()
        let ours = try privateReply(from: alice, toANoteBy: bob, read: alice)

        // A draft that mentions a third party, as `build_post` would render one.
        var tags = nip10_reply_tags(replying_to: ours, keypair: alice.to_keypair(), relayURL: nil)
        tags.append(["p", carol.pubkey.hex()])
        let built = try NIP59.createPrivateReply(NostrPost(content: "still just us", tags: tags),
                                                 replyingTo: ours,
                                                 keypair: alice)

        XCTAssertEqual(built.audience, bob.pubkey)
        XCTAssertEqual(built.rumor.tags.filter({ $0.first == "p" }), [["p", bob.pubkey.hex()]],
                       "exactly one p tag, and carol is not in it — the audience never widens")
        XCTAssertTrue(built.rumor.tags.contains(where: { $0.first == "e" && $0[safe: 1] == ours.id.hex() }),
                      "the e tag points at the rumor, which resolves for exactly the two people who have it")
        XCTAssertEqual(built.giftWraps.count, 2)
        XCTAssertEqual(Set(built.giftWraps.map({ $0.referenced_pubkeys.first })), [alice.pubkey, bob.pubkey],
                       "one wrap to us, one to bob — and none to carol")
    }

    // MARK: A pubkey-only login

    /// A pubkey-only login can *read* a private reply but cannot seal one, and there is no public
    /// reply for it to fall back to. So the affordance is absent, at both levels the card names.
    @MainActor
    func testAPubkeyOnlyLoginCannotReplyToAPrivateReply() throws {
        let alice = test_keypair_full
        let bob = generate_new_keypair()
        let parent = try privateReply(from: bob, toANoteBy: alice, read: alice)
        let watch_only = Keypair(pubkey: alice.pubkey, privkey: nil)

        XCTAssertFalse(NoteActions.available(on: parent, keypair: watch_only).contains(.reply),
                       "the action bar and the swipe menu offer no reply button")

        let composer = PostView(action: .replying_to(parent), damus_state: make_test_damus_state(keypair: watch_only))
        XCTAssertFalse(composer.can_reply_privately)
        XCTAssertTrue(composer.private_reply_required)
        XCTAssertTrue(composer.posting_disabled,
                      "and if the composer is opened anyway, it cannot post a public reply out of it")
    }

    // MARK: Helpers

    /// A real private reply from `sender` to a public note by `receiver`, as `read` gets it out of
    /// nostrdb — which is the only way to obtain a note whose ``NdbNote/is_rumor`` flag is genuine.
    private func privateReply(from sender: FullKeypair, toANoteBy receiver: FullKeypair, read reader: FullKeypair) throws -> NostrEvent {
        let parent = try XCTUnwrap(NostrEvent(content: "a public note", keypair: receiver.to_keypair(),
                                              kind: NostrKind.text.rawValue, tags: []))
        let tags = nip10_reply_tags(replying_to: parent, keypair: sender.to_keypair(), relayURL: nil)
        let built = try NIP59.createPrivateReply(NostrPost(content: "between us", tags: tags),
                                                 replyingTo: parent,
                                                 keypair: sender)
        let wrap = reader.pubkey == sender.pubkey ? built.giftWrapToSelf : try XCTUnwrap(built.giftWrapToReceiver)

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
        let rumor = try XCTUnwrap(try ndb.lookup_note_by_key_and_copy(key))
        XCTAssertTrue(rumor.is_private_reply, "fixture is only meaningful if nostrdb flagged it")
        return rumor
    }
}
