//
//  PrivateReplyActionTests.swift
//  damusTests
//
//  Created by Claude on 2026-09-05.
//

import XCTest
@testable import damus

/// Covers ``NoteActions/available(on:keypair:)`` — the value the note menu and the action bar are *built
/// from*, so these are assertions on the built menu rather than on a guard that fires after a tap.
///
/// This is the containment that survived: a private reply is drawn everywhere a public note is,
/// marked with a lock, and what is withheld is not the note but what can be *published* about it.
/// Every action asserted absent here would have published a new, correctly signed event that embeds
/// the rumor or points at it — none of which the relay-egress guards in `PostBox.send` and
/// ``make_nostr_push_event(ev:)`` would refuse, because none of them is a rumor.
///
/// The line is "publishes, with no private form available", not "does anything at all". Reply and
/// react both publish and both stay, because each becomes a rumor in its own gift wrap. An earlier
/// version of this class asserted react absent; that was the right diagnosis of the leak and the
/// wrong remedy.
final class PrivateReplyActionTests: XCTestCase {

    // MARK: Fixtures

    /// Runs `wrap` through a real nostrdb with `reader`'s key registered and hands back the rumor
    /// that comes out — the only way to get a note whose ``NdbNote/is_rumor`` flag is genuine. The
    /// flag is written by nostrdb's unwrapper and by nothing else, which is what makes it a
    /// predicate nobody can forge.
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

    /// A real private reply from `sender` to a public note by `receiver`, as `sender` reads their own
    /// copy back out of the database.
    private func privateReply(from sender: FullKeypair, toANoteBy receiver: FullKeypair) throws -> (reply: NostrEvent, parent: NostrEvent) {
        let parent = try XCTUnwrap(NostrEvent(content: "a public note", keypair: receiver.to_keypair(),
                                              kind: NostrKind.text.rawValue, tags: []))
        let tags = nip10_reply_tags(replying_to: parent, keypair: sender.to_keypair(), relayURL: nil)
        let built = try NIP59.createPrivateReply(NostrPost(content: "between us", tags: tags),
                                                 replyingTo: parent,
                                                 keypair: sender)
        let rumor = try ingestedRumor(built.giftWrapToSelf, as: sender, kinds: [.text])
        XCTAssertTrue(rumor.is_private_reply, "fixture is only meaningful if nostrdb flagged it")
        return (rumor, parent)
    }

    // MARK: The public baseline

    /// Nothing changes for an ordinary note. Stated first because every assertion below is only
    /// interesting as a difference from this one.
    func testAPublicNoteOffersEverything() throws {
        let alice = generate_new_keypair()
        let note = try XCTUnwrap(NostrEvent(content: "hello world", keypair: alice.to_keypair(),
                                            kind: NostrKind.text.rawValue, tags: []))

        XCTAssertEqual(NoteActions.available(on: note, keypair: alice.to_keypair()), .all,
                       "a public note loses nothing")
    }

    /// A signed kind 1 is never treated as private, however it is tagged — the same converse
    /// ``NdbNote/is_private_reply`` rests on. Otherwise anyone could publish a note that strips the
    /// boost button off itself, which is a nuisance rather than a leak but is still theirs to decide
    /// rather than ours.
    func testATagCannotMakeAPublicNotePrivate() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let impostor = try XCTUnwrap(NostrEvent(
            content: "not private, whatever it says",
            keypair: alice.to_keypair(),
            kind: NostrKind.text.rawValue,
            tags: [["p", bob.pubkey.hex()], ["private", ""]]
        ))

        XCTAssertEqual(NoteActions.available(on: impostor, keypair: bob.to_keypair()), .all)
    }

    // MARK: A private reply

    /// The whole rule in one assertion: everything that would republish the reply or hand out a
    /// pointer to it is gone, and the three things that have a private form survive.
    func testAPrivateReplyOffersOnlyWhatHasAPrivateForm() throws {
        let alice = generate_new_keypair()
        let (reply, _) = try privateReply(from: alice, toANoteBy: generate_new_keypair())

        XCTAssertEqual(NoteActions.available(on: reply, keypair: alice.to_keypair()), [.reply, .like])
    }

    /// Named individually, because each one is a distinct leak and a regression on any single one
    /// would otherwise show up only as an opaque set mismatch.
    ///
    /// Every reason below is the same reason: the action *publishes*, and there is no version of it
    /// that does not. That is what separates this list from reacting, which publishes too and is kept
    /// — see ``testAPrivateReplyCanBeReactedToInPrivate()``.
    func testEveryRepublishingActionIsAbsentFromAPrivateReply() throws {
        let alice = generate_new_keypair()
        let (reply, _) = try privateReply(from: alice, toANoteBy: generate_new_keypair())
        let actions = NoteActions.available(on: reply, keypair: alice.to_keypair())

        XCTAssertFalse(actions.contains(.repost),
                       "a kind 6 embeds the rumor's JSON in its content and is itself a perfectly ordinary signed event, so no egress guard would stop it — this is the worst one")
        XCTAssertFalse(actions.contains(.broadcast),
                       "Broadcast is refused at egress, but silently — the item has to be gone, not inert")
        XCTAssertFalse(actions.contains(.copyJSON),
                       "Copy note JSON puts the plaintext and a bogus signature on the system pasteboard, and nothing downstream stops it")
        XCTAssertFalse(actions.contains(.share),
                       "an nevent for a rumor is a link nobody else can resolve")
        XCTAssertFalse(actions.contains(.report),
                       "a NIP-56 report is a public event naming a note no moderator can fetch, and it announces the private exchange")
        XCTAssertFalse(actions.contains(.zap),
                       "and a zap request names the note and its author — still true, and a private form of it is separate work")
    }

    /// **React is offered, and was not.**
    ///
    /// It was removed for a real reason: a kind 7 publishes a *public* event naming the note and,
    /// through its `p` tag, its author — announcing to a relay that a private note reached you and who
    /// sent it, which is the correlation the wrap exists to prevent. That reasoning was right about
    /// the leak and wrong about the fix. Withholding the affordance is only the right answer when the
    /// action has no private form, and this one has: a reaction to a rumor becomes a kind-7 *rumor* in
    /// its own gift wrap (`PrivateReactionTests`).
    ///
    /// So this flag now means "may react", not "may publish a kind 7". The assertion here is only that
    /// the affordance exists; that it takes the private path when tapped is asserted in that class,
    /// against what actually leaves the device.
    func testAPrivateReplyCanBeReactedToInPrivate() throws {
        let alice = generate_new_keypair()
        let (reply, _) = try privateReply(from: alice, toANoteBy: generate_new_keypair())
        let actions = NoteActions.available(on: reply, keypair: alice.to_keypair())

        XCTAssertTrue(actions.contains(.like),
                      "the reaction has a private form — a kind-7 rumor in its own wrap — so the button stays")
    }

    /// But not without a key. A private reaction is a rumor we have to seal, exactly as a private
    /// reply is, so a pubkey-only login cannot make one — and the button has to be absent rather than
    /// present and failing, for the same reason reply is: there is no public fallback a private
    /// reaction could quietly become.
    ///
    /// Taking the button away on a public note is not this feature's business, which is the second
    /// assertion below.
    func testAPubkeyOnlyLoginCannotReactToAPrivateReply() throws {
        let alice = generate_new_keypair()
        let (reply, _) = try privateReply(from: alice, toANoteBy: generate_new_keypair())

        let actions = NoteActions.available(on: reply, keypair: Keypair(pubkey: alice.pubkey, privkey: nil))
        XCTAssertFalse(actions.contains(.like), "no key to sign the seal with")
        XCTAssertFalse(actions.contains(.reply), "for the same reason")

        let publicNote = try XCTUnwrap(NostrEvent(content: "public", keypair: alice.to_keypair(),
                                                  kind: NostrKind.text.rawValue, tags: []))
        XCTAssertTrue(NoteActions.available(on: publicNote, keypair: Keypair(pubkey: alice.pubkey, privkey: nil)).contains(.like),
                      "while the public app is untouched — that is a signing sheet's job, not this one's")
    }

    /// Reply stays. Phase 6 is what makes the reply it opens private in turn; taking the affordance
    /// away here would instead make a private reply unanswerable.
    func testReplyRemainsOnAPrivateReply() throws {
        let alice = generate_new_keypair()
        let (reply, _) = try privateReply(from: alice, toANoteBy: generate_new_keypair())

        XCTAssertTrue(NoteActions.available(on: reply, keypair: alice.to_keypair()).contains(.reply))
    }

    /// Mute conversation is gone too, and this is the case that says why it has to be.
    ///
    /// A kind-1 rumor is *any* note another client chose to send inside a gift wrap, and nothing
    /// obliges it to be a reply — only the notes this app builds are, because the builder refuses to
    /// make any other kind. With no root ref, `thread_id()` falls back to the note's own id, so
    /// offering the action here would publish the rumor's id in our public mutelist: an id nobody
    /// outside the wrap has ever seen.
    func testMuteIsGoneBecauseAKindOneRumorNeedNotBeAReply() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()

        // What another client can send us: a kind-1 rumor with no reply tags at all.
        let rumor = NIP59.Rumor(pubkey: bob.pubkey,
                                kind: NostrKind.text.rawValue,
                                tags: [["p", alice.pubkey.hex()]],
                                content: "a private note that answers nothing",
                                createdAt: UInt32(Date().timeIntervalSince1970))
        let wrap = try NIP59.giftWrap(rumor: rumor, sender: bob, receiver: alice.pubkey)
        let received = try ingestedRumor(wrap, as: alice, kinds: [.text])

        XCTAssertTrue(received.is_private_reply, "the predicate matches it, reply or not — which is the point")
        XCTAssertEqual(received.thread_id(), received.id,
                       "so its thread id is the rumor itself, and muting would publish that id")
        XCTAssertFalse(NoteActions.available(on: received, keypair: alice.to_keypair()).contains(.muteThread))
    }

    /// And gone for an ordinary private reply as well, rather than by a case analysis of which rumors
    /// happen to carry a public parent. The action is worth little here — muting a private reply's
    /// conversation only ever meant muting its public parent thread, which is reachable from the
    /// parent note directly above it — and a rule that holds for every rumor is worth more than one
    /// that has to be re-argued each time somebody adds a caller.
    func testMuteIsGoneForAnOrdinaryPrivateReplyToo() throws {
        let alice = generate_new_keypair()
        let (reply, parent) = try privateReply(from: alice, toANoteBy: generate_new_keypair())

        XCTAssertFalse(NoteActions.available(on: reply, keypair: alice.to_keypair()).contains(.muteThread))
        XCTAssertEqual(reply.thread_id(), parent.id,
                       "even though this one's thread id is in fact the public parent")
    }

    // MARK: DMs, which are rumors too

    /// A NIP-17 DM reaches the same menu — `DMChatView` builds `MenuItems` for one — and is a rumor
    /// for the same reason, so the same items go. Mute conversation was already excluded for a DM by
    /// kind; it is now excluded because it is a rumor, which is the same answer reached by the reason
    /// the kind check was standing in for.
    func testADirectMessageLosesTheSameActionsAndKeepsNoMute() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let dm = try NIP17.createDirectMessage("hi bob", to: bob.pubkey, keypair: alice)
        let rumor = try ingestedRumor(dm.giftWrapToSelf, as: alice, kinds: [.private_dm])

        XCTAssertTrue(rumor.is_rumor)
        XCTAssertEqual(NoteActions.available(on: rumor, keypair: alice.to_keypair()), [.reply, .like],
                       "a DM keeps the same two, by the same rumor rule rather than by its kind")
        XCTAssertEqual(rumor.thread_id(), rumor.id,
                       "and here is the thread id that rule protects: the rumor itself")
    }
}
