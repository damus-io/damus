//
//  PrivateReactionTests.swift
//  damusTests
//
//  Created by Claude on 2026-09-05.
//

import XCTest
@testable import damus

/// Covers reacting to something that came out of a gift wrap:
/// ``NIP59/createPrivateReaction(to:content:keypair:createdAt:)``, the branch in
/// ``send_reaction(to:emoji:keypair:damus_state:)`` that chooses it, and the receive side that has to
/// pick the result up again.
///
/// A reaction is a smaller thing than a reply and it leaks in a larger way. A kind 7 is *public by
/// construction*: it names the note it reacts to and that note's author, so on a note only two people
/// hold it tells a relay both that the note exists and who is talking to whom — while the note itself,
/// the thing everyone worries about, stays encrypted. That is why the affordance was removed
/// outright at first. The answer here is the opposite one: keep the affordance and make the reaction
/// as private as the thing it reacts to.
///
/// Every fixture goes through a **real** `Ndb` with the reader's key registered, because
/// ``NdbNote/is_rumor`` is written by nostrdb's unwrapper and by nothing else. A hand-built kind 7
/// with the right fields would prove nothing at all: the flag is exactly what cannot be forged, and
/// the flag is what every decision here keys off.
final class PrivateReactionTests: XCTestCase {

    // MARK: What gets built

    /// The shape of the thing: a kind-7 rumor naming the private reply, addressed to its sender.
    func testAReactionToAPrivateReplyIsAKindSevenRumorAddressedToItsSender() throws {
        let alice = generate_new_keypair()   // us, the reader
        let bob = generate_new_keypair()     // who sent us the private reply
        let reply = try inboundPrivateReply(from: bob, toANoteBy: alice, readAs: alice)

        let reaction = try NIP59.createPrivateReaction(to: reply, content: "🤙", keypair: alice)

        XCTAssertEqual(reaction.rumor.kind, NostrKind.like.rawValue)
        XCTAssertEqual(reaction.rumor.content, "🤙")
        XCTAssertEqual(reaction.rumor.pubkey, alice.pubkey)
        XCTAssertEqual(reaction.audience, bob.pubkey, "addressed to whoever sent the note we reacted to")
        XCTAssertEqual(reaction.giftWraps.count, 2, "one wrap for them, one for us, and nothing else")
        for wrap in reaction.giftWraps {
            XCTAssertEqual(wrap.kind, NostrKind.giftwrap.rawValue)
        }
    }

    /// **The tags, which are the whole design.** `make_like_event` copies every `e` and `p` tag off
    /// the note it reacts to, because NIP-25 wants a public kind 7 routable to everyone following that
    /// thread. A rumor is routed by its wrap and served to nobody, so it carries one `e` naming what
    /// was reacted to and one `p` naming the audience — no more.
    ///
    /// The `p` tag is the part that matters. On a rumor a `p` tag is not a mention, it is a delivery
    /// address, so an extra one either widens the audience in another client's eyes or promises a
    /// delivery that is never made. The parent's own `p` tag, and the public thread tags it carries,
    /// are what a copying implementation would drag in.
    func testTheReactionCarriesOneReferenceAndOneAddressee() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let carol = generate_new_keypair()

        // A private reply that sits inside a public thread, so its own tags carry a root `e`, a reply
        // `e` and a `p` — exactly the three things a copying implementation would drag into the kind 7.
        let root = try XCTUnwrap(NostrEvent(content: "carol's public note", keypair: carol.to_keypair(),
                                            kind: NostrKind.text.rawValue, tags: []))
        let ourPublicReply = try XCTUnwrap(NostrEvent(content: "alice answers in public", keypair: alice.to_keypair(),
                                                      kind: NostrKind.text.rawValue,
                                                      tags: nip10_reply_tags(replying_to: root, keypair: alice.to_keypair(), relayURL: nil)))
        let reply = try inboundPrivateReply(from: bob, to: ourPublicReply, readAs: alice)
        XCTAssertTrue(reply.referenced_ids.contains(root.id), "fixture: the reply names the public root above it")
        XCTAssertTrue(reply.referenced_pubkeys.contains(alice.pubkey), "fixture: and it is addressed to us")

        let reaction = try NIP59.createPrivateReaction(to: reply, content: "+", keypair: alice)

        XCTAssertEqual(reaction.rumor.tags,
                       [["e", reply.id.hex()], ["p", bob.pubkey.hex()]],
                       "one reference and one addressee, in that order and with nothing else")
        XCTAssertFalse(reaction.rumor.tags.contains(where: { $0.contains(root.id.hex()) }),
                       "the public thread's root buys no reader anything inside the encryption")
        XCTAssertFalse(reaction.rumor.tags.contains(where: { $0.contains(alice.pubkey.hex()) }),
                       "and copying the parent's p tag would have added a second delivery address — ourselves")
    }

    /// Reacting to a private reply **of our own** goes to the person we sent it to, not to ourselves.
    ///
    /// The same trap ``NIP59/privateAudience(for:as:)`` exists for on the reply path, and it is easier
    /// to fall into here because reacting to your own note is an ordinary thing to do by accident.
    /// Addressing it to ourselves would produce a reaction only we can see, on a note the other person
    /// is looking at.
    func testReactingToOurOwnPrivateReplyGoesToTheCounterparty() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let ours = try ourOwnPrivateReply(from: alice, toANoteBy: bob)
        XCTAssertEqual(ours.pubkey, alice.pubkey, "fixture: this is our own note")

        let reaction = try NIP59.createPrivateReaction(to: ours, content: "🤙", keypair: alice)

        XCTAssertEqual(reaction.audience, bob.pubkey,
                       "the conversation is with bob, so reacting in it is addressed to bob")
        XCTAssertEqual(reaction.rumor.tags.last, ["p", bob.pubkey.hex()])
        XCTAssertNotNil(reaction.giftWrapToReceiver, "so there is a second wrap to publish")
    }

    /// Two wraps, two ephemeral keys, and no way to tell from the relay that they are a pair.
    ///
    /// Restated for the reaction path rather than inherited from the reply's test, because the two
    /// call ``NIP59/giftWrap(rumor:sender:receiver:now:)`` separately and a builder that generated one
    /// key and reused it would pass every other assertion in this file. Reusing the key is a total
    /// deanonymisation: two wraps signed by one throwaway pubkey are provably from the same sender.
    func testTheTwoWrapsShareNothingThatWouldLinkThem() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let reply = try inboundPrivateReply(from: bob, toANoteBy: alice, readAs: alice)

        let reaction = try NIP59.createPrivateReaction(to: reply, content: "🤙", keypair: alice)
        let theirs = try XCTUnwrap(reaction.giftWrapToReceiver)
        let ours = reaction.giftWrapToSelf

        XCTAssertNotEqual(theirs.pubkey, ours.pubkey, "a fresh throwaway key each, never one reused")
        XCTAssertNotEqual(theirs.pubkey, alice.pubkey, "and neither of them is us")
        XCTAssertNotEqual(ours.pubkey, alice.pubkey)
        XCTAssertNotEqual(theirs.content, ours.content, "sealed to different keys, so different ciphertext")
        XCTAssertEqual(Array(theirs.referenced_pubkeys), [bob.pubkey])
        XCTAssertEqual(Array(ours.referenced_pubkeys), [alice.pubkey])
    }

    /// Reacting to a **public** note privately is refused, rather than quietly producing a reaction
    /// only one person can see.
    ///
    /// The guard is ``NdbNote/is_rumor`` and not a kind check, so this holds for a signed kind 1 no
    /// matter how it is tagged — the same converse the rest of the feature rests on.
    func testAPrivateReactionToAPublicNoteIsRefused() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let publicNote = try XCTUnwrap(NostrEvent(content: "hello world", keypair: bob.to_keypair(),
                                                  kind: NostrKind.text.rawValue,
                                                  tags: [["p", alice.pubkey.hex()], ["private", ""]]))

        XCTAssertThrowsError(try NIP59.createPrivateReaction(to: publicNote, content: "🤙", keypair: alice)) { error in
            XCTAssertEqual(error as? NIP59.PrivateReactionError, .notPrivate)
        }
    }

    // MARK: The round trip

    /// The recipient opens the wrap addressed to them and finds a reaction naming the right note.
    ///
    /// Both parties, out of separate databases, cross-checked at the end — the only thing that makes
    /// it *one* reaction rather than two is that the rumor inside both wraps is identical, which
    /// neither half shows on its own.
    func testBothPartiesReadTheSameReactionOutOfTheirOwnWrap() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let reply = try inboundPrivateReply(from: bob, toANoteBy: alice, readAs: alice)

        let reaction = try NIP59.createPrivateReaction(to: reply, content: "❤️", keypair: alice)
        let ours = try ingestedRumor(reaction.giftWrapToSelf, as: alice, kinds: [.like])
        let theirs = try ingestedRumor(try XCTUnwrap(reaction.giftWrapToReceiver), as: bob, kinds: [.like])

        for (who, got) in [("sender", ours), ("recipient", theirs)] {
            XCTAssertEqual(got.kind, 7, "\(who): an ordinary kind 7 once unwrapped")
            XCTAssertTrue(got.is_rumor, "\(who): flagged by nostrdb's unwrapper, which is the unforgeable part")
            XCTAssertFalse(got.is_private_reply, "\(who): a rumor, but not a kind-1 one")
            XCTAssertEqual(got.content, "❤️", "\(who)")
            XCTAssertEqual(got.pubkey, alice.pubkey, "\(who): the real reactor, copied off the seal")
            XCTAssertEqual(got.last_refid(), reply.id,
                           "\(who): and `handle_like_event` reads the target off exactly this")
        }

        XCTAssertEqual(ours.id, theirs.id, "one reaction, despite two wraps, two seals and two ephemeral keys")
    }

    /// The receive side, which is the assertion that makes the feature worth shipping: a private
    /// reaction that never appears on the note is a message into a void.
    ///
    /// Nothing new was written for this. nostrdb peels any rumor kind, and the notification filter the
    /// home model already runs — `kinds: [1, 6, 7, 9735]`, `#p: <us>` — matches a kind-7 rumor
    /// addressed to us out of the *local* database. So the test drives `handle_like_event` with what
    /// nostrdb produced and asserts the count landed on the reply.
    @MainActor
    func testAnInboundPrivateReactionIsCountedOnTheNoteItNames() throws {
        let alice = test_keypair_full           // us
        let bob = generate_new_keypair()        // who reacts to our private reply
        let state = make_test_damus_state(keypair: alice.to_keypair())

        let ourReply = try ourOwnPrivateReply(from: alice, toANoteBy: bob)
        let reaction = try NIP59.createPrivateReaction(to: ourReply, content: "🤙", keypair: bob)
        let inbound = try ingestedRumor(try XCTUnwrap(reaction.giftWrapToReceiver), as: alice, kinds: [.like])

        // The reaction is addressed to us, which is both what the wrap delivers on and what makes the
        // existing `#p: <us>` notification filter match it.
        XCTAssertEqual(Array(inbound.referenced_pubkeys), [alice.pubkey])

        let home = HomeModel()
        home.damus_state = state
        home.process_event(ev: inbound, context: .notifications)

        XCTAssertEqual(state.likes.counts[ourReply.id], 1,
                       "the private reaction shows on the note, through the ordinary counting path")
        XCTAssertNil(state.likes.our_events[ourReply.id],
                     "and it is recorded as bob's, not as one of ours")
    }

    // MARK: The branch, and what leaves the device

    /// A reaction to a public note is still a public kind 7. Stated first because everything else here
    /// is only interesting as a difference from it.
    @MainActor
    func testReactingToAPublicNoteIsStillAPublicKindSeven() async throws {
        let state = make_test_damus_state()
        let bob = generate_new_keypair()
        let note = try XCTUnwrap(NostrEvent(content: "a public note", keypair: bob.to_keypair(), kind: 1, tags: []))
        try state.ndb.add(event: note)

        let posted = await send_reaction(to: note, emoji: "🤙", keypair: test_keypair_full, damus_state: state)
        let sent = try XCTUnwrap(posted)

        XCTAssertEqual(sent.kind, 7)
        XCTAssertTrue(sent.verify(), "signed by us, which is what makes it public")
        XCTAssertFalse(sent.is_rumor)

        let queued = await state.nostrNetwork.postbox.events
        XCTAssertEqual(queued.count, 1)
        XCTAssertEqual(queued.values.first?.event.kind, 7, "and it goes to the relay as itself")
    }

    /// **The negative that matters.** Across a whole private reaction send, nothing but kind 1059
    /// reaches `PostBox`, and no outbound frame's JSON contains the emoji, the reaction's id, the id
    /// of the note it reacts to, or us.
    ///
    /// A kind check alone would not catch a wrap whose encryption silently stopped happening, and the
    /// reacted-to id is the one field a reaction has that a reply does not — leaking it names a note
    /// that exists nowhere.
    @MainActor
    func testNoOutboundFrameContainsTheReactionTheNoteItNamesOrUs() async throws {
        let state = make_test_damus_state()
        XCTAssertTrue(state.ndb.add_key(test_keypair_full.privkey))
        let bob = generate_new_keypair()
        let reply = try inboundPrivateReply(from: bob, toANoteBy: test_keypair_full, readAs: test_keypair_full)

        let emoji = "🦞"
        let posted = await send_reaction(to: reply, emoji: emoji, keypair: test_keypair_full, damus_state: state)
        let sent = try XCTUnwrap(posted)
        XCTAssertTrue(sent.is_rumor, "what comes back is nostrdb's copy, so it is refused by both egress guards")
        XCTAssertEqual(sent.kind, 7)

        let queued = await state.nostrNetwork.postbox.events
        XCTAssertEqual(queued.count, 2, "one wrap per addressee, and nothing else")

        for posted in queued.values {
            let json = try XCTUnwrap(encode_json(posted.event))
            XCTAssertEqual(posted.event.kind, 1059, "only wraps leave the device")
            XCTAssertFalse(json.contains(emoji), "the reaction must not appear in an outbound frame")
            XCTAssertFalse(json.contains(reply.id.hex()),
                           "nor the id of the note it names, which exists on no relay")
            XCTAssertFalse(json.contains(sent.id.hex()), "nor the reaction's own id")
            XCTAssertNotEqual(posted.event.pubkey, state.pubkey, "our own key must never sign a wrap")
        }

        // Our pubkey belongs in exactly one frame: the `p` tag on the copy addressed to us, which is
        // how a relay routes it to our own inbox. In the other one it would tie the two wraps together
        // and identify the reactor.
        let theirs = try XCTUnwrap(queued.values.first(where: { $0.event.referenced_pubkeys.first != state.pubkey }))
        XCTAssertFalse(try XCTUnwrap(encode_json(theirs.event)).contains(state.pubkey.hex()),
                       "the recipient's wrap says nothing about who reacted")
        XCTAssertFalse(queued.keys.contains(sent.id), "the rumor itself is never queued")
    }

    // MARK: Fixtures

    /// Runs `wrap` through a real nostrdb with `reader`'s key registered and hands back the rumor that
    /// comes out — the only way to get a note whose ``NdbNote/is_rumor`` flag is genuine.
    private func ingestedRumor(_ wrap: NostrEvent, as reader: FullKeypair, kinds: [NostrKind]) throws -> NostrEvent {
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

        let filter = try NdbFilter(from: NostrFilter(kinds: kinds))
        let key = try XCTUnwrap(try ndb.query(filters: [filter], maxResults: 10).first)
        return try XCTUnwrap(try ndb.lookup_note_by_key_and_copy(key))
    }

    /// A private reply `sender` wrote answering a public note by `parentAuthor`, as `reader` reads it.
    private func inboundPrivateReply(from sender: FullKeypair,
                                     toANoteBy parentAuthor: FullKeypair,
                                     readAs reader: FullKeypair) throws -> NostrEvent {
        let parent = try XCTUnwrap(NostrEvent(content: "a public note", keypair: parentAuthor.to_keypair(),
                                              kind: NostrKind.text.rawValue, tags: []))
        return try inboundPrivateReply(from: sender, to: parent, readAs: reader)
    }

    /// The same, for a parent the caller built, so a test can put a third party in the public thread.
    private func inboundPrivateReply(from sender: FullKeypair,
                                     to parent: NostrEvent,
                                     readAs reader: FullKeypair) throws -> NostrEvent {
        let tags = nip10_reply_tags(replying_to: parent, keypair: sender.to_keypair(), relayURL: nil)
        let built = try NIP59.createPrivateReply(NostrPost(content: "between us", tags: tags),
                                                 replyingTo: parent, keypair: sender)
        let wrap = sender.pubkey == reader.pubkey ? built.giftWrapToSelf : try XCTUnwrap(built.giftWrapToReceiver)
        let rumor = try ingestedRumor(wrap, as: reader, kinds: [.text])
        XCTAssertTrue(rumor.is_private_reply, "fixture is only meaningful if nostrdb flagged it")
        return rumor
    }

    /// A private reply *we* sent, read back out of our own wrap.
    private func ourOwnPrivateReply(from us: FullKeypair, toANoteBy them: FullKeypair) throws -> NostrEvent {
        return try inboundPrivateReply(from: us, toANoteBy: them, readAs: us)
    }
}
