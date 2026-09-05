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
/// marked with a lock, and what is withheld is not the note but what can be done with it. Every
/// action asserted absent here would have published a new, correctly signed event that embeds the
/// rumor or points at it — none of which the relay-egress guards in `PostBox.send` and
/// ``make_nostr_push_event(ev:)`` would refuse, because none of them is a rumor.
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

    /// The whole card in one assertion: everything that republishes the reply or points at it is
    /// gone, and reply survives.
    func testAPrivateReplyOffersOnlyReply() throws {
        let alice = generate_new_keypair()
        let (reply, _) = try privateReply(from: alice, toANoteBy: generate_new_keypair())

        XCTAssertEqual(NoteActions.available(on: reply, keypair: alice.to_keypair()), [.reply])
    }

    /// Named individually, because each one is a distinct leak and a regression on any single one
    /// would otherwise show up only as an opaque set mismatch.
    func testEveryRepublishingActionIsAbsentFromAPrivateReply() throws {
        let alice = generate_new_keypair()
        let (reply, _) = try privateReply(from: alice, toANoteBy: generate_new_keypair())
        let actions = NoteActions.available(on: reply, keypair: alice.to_keypair())

        XCTAssertFalse(actions.contains(.repost),
                       "a kind 6 embeds the rumor's JSON in its content and is itself a perfectly ordinary signed event, so no egress guard would stop it — this is the worst one")
        XCTAssertFalse(actions.contains(.like),
                       "a kind 7 names the note and its author, announcing that a private reply reached us and from whom")
        XCTAssertFalse(actions.contains(.zap),
                       "a zap request names the note and its author for the same reason")
        XCTAssertFalse(actions.contains(.broadcast),
                       "Broadcast is refused at egress, but silently — the item has to be gone, not inert")
        XCTAssertFalse(actions.contains(.copyJSON),
                       "Copy note JSON puts the plaintext and a bogus signature on the system pasteboard, and nothing downstream stops it")
        XCTAssertFalse(actions.contains(.share),
                       "an nevent for a rumor is a link nobody else can resolve")
        XCTAssertFalse(actions.contains(.report),
                       "a NIP-56 report is a public event naming a note no moderator can fetch, and it announces the private exchange")
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
        XCTAssertEqual(NoteActions.available(on: rumor, keypair: alice.to_keypair()), [.reply],
                       "a DM keeps only reply, by the same rumor rule rather than by its kind")
        XCTAssertEqual(rumor.thread_id(), rumor.id,
                       "and here is the thread id that rule protects: the rumor itself")
    }
}
