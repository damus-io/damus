//
//  PrivateReplyIngestTests.swift
//  damusTests
//
//  Created by Claude on 2026-09-05.
//

import XCTest
@testable import damus

/// Covers ``NdbNote/is_private_reply`` — the one predicate the whole read side keys off — through
/// **real nostrdb**, against wraps the real builder produced.
///
/// Testing this against a hand-built fixture would prove nothing: the predicate reads
/// `NDB_NOTE_FLAG_RUMOR`, a flag no test can set and only nostrdb's unwrapper writes, so the only
/// way to know it is true of a private reply is to put one through the ingester and read it back.
///
/// The negative cases matter as much as the positive one. A signed kind 1 must never satisfy this
/// however it is tagged — that is what stops anyone publishing themselves a lock badge in someone
/// else's thread — and a kind-14 DM rumor must not either, or the DM path and the thread path would
/// start showing each other's notes.
final class PrivateReplyIngestTests: XCTestCase {

    /// A private reply, unwrapped by the key it was addressed to, is recognised as one.
    func testAnIngestedPrivateReplyIsAPrivateReply() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let parent = try Self.publicNote(by: bob, content: "a public note")

        let reply = try NIP59.createPrivateReply(Self.replyPost(to: parent, from: alice, content: "only for you"),
                                                 replyingTo: parent,
                                                 keypair: alice)

        // Alice's own copy: the wrap she addressed to herself, which is how a sent private reply
        // reaches her thread view.
        let ndb = try Self.ingest(reply.giftWrapToSelf, unwrappingWith: alice)
        defer { ndb.close() }

        let rumor = try XCTUnwrap(Self.firstNote(ofKind: .text, in: ndb))

        XCTAssertTrue(rumor.is_private_reply)
        XCTAssertTrue(rumor.is_rumor, "the flag only nostrdb's unwrapper sets")
        XCTAssertEqual(rumor.kind, 1)
        XCTAssertEqual(rumor.content, "only for you", "the stored rumor is plaintext")
        XCTAssertEqual(rumor.pubkey, alice.pubkey, "nostrdb copies the sender pubkey off the seal")
        XCTAssertEqual(rumor.thread_reply()?.reply.note_id, parent.id,
                       "the reply tags survive the round trip, so it lands in the right thread")
    }

    /// The recipient's side of the same send. Different key, different wrap, same predicate — the
    /// person receiving a private reply has to recognise it as one just as the sender does.
    func testTheRecipientsCopyIsAlsoAPrivateReply() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let parent = try Self.publicNote(by: bob, content: "bob says something")

        let reply = try NIP59.createPrivateReply(Self.replyPost(to: parent, from: alice, content: "answering you privately"),
                                                 replyingTo: parent,
                                                 keypair: alice)

        let ndb = try Self.ingest(try XCTUnwrap(reply.giftWrapToReceiver), unwrappingWith: bob)
        defer { ndb.close() }

        let rumor = try XCTUnwrap(Self.firstNote(ofKind: .text, in: ndb))

        XCTAssertTrue(rumor.is_private_reply)
        XCTAssertEqual(rumor.content, "answering you privately", "bob reads the same content alice sent")
        XCTAssertEqual(rumor.pubkey, alice.pubkey, "and knows it was alice who sent it")
        XCTAssertEqual(rumor.rumor_receiver_pubkey, bob.pubkey)
        XCTAssertEqual(rumor.thread_reply()?.reply.note_id, parent.id, "pointing at the same parent")
    }

    /// A NIP-17 DM is a rumor too. The predicate has to be about kind 1 specifically, or every DM in
    /// the database would start claiming to be a reply in some thread.
    func testAKind14DirectMessageIsNotAPrivateReply() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()

        let dm = try NIP17.createDirectMessage("just a dm", to: bob.pubkey, keypair: alice)
        let ndb = try Self.ingest(dm.giftWrapToSelf, unwrappingWith: alice)
        defer { ndb.close() }

        let rumor = try XCTUnwrap(Self.firstNote(ofKind: .private_dm, in: ndb))

        XCTAssertTrue(rumor.is_rumor)
        XCTAssertFalse(rumor.is_private_reply, "a DM is a rumor, but it is not a kind-1 reply")
    }

    /// The assertion that keeps the lock honest: nobody can publish themselves one.
    ///
    /// A signed kind 1 arriving from a relay is a public note no matter what it carries — the reply
    /// tags of a private reply, a `p` tag naming a single audience, a tag that says "private" in so
    /// many words. The rumor flag is written by nostrdb's unwrapper and by nothing else, so there is
    /// nothing to forge.
    func testASignedKindOneIsNeverAPrivateReplyHoweverItIsTagged() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let parent = try Self.publicNote(by: bob, content: "a public note")

        let impostor = try XCTUnwrap(NostrEvent(
            content: "this is not private, whatever it says",
            keypair: alice.to_keypair(),
            kind: NostrKind.text.rawValue,
            tags: [["e", parent.id.hex(), "", "root", bob.pubkey.hex()],
                   ["p", bob.pubkey.hex()],
                   ["private", ""]]
        ))

        let ndb = try Self.seeded(with: [impostor])
        defer { ndb.close() }

        let stored = try XCTUnwrap(Self.firstNote(ofKind: .text, in: ndb))
        XCTAssertFalse(stored.is_rumor)
        XCTAssertFalse(stored.is_private_reply, "a relay cannot hand anyone a lock badge")
        XCTAssertTrue(stored.verify(), "it is an ordinary, verifiable public note")
    }

    /// The wrap is an ordinary signed note in its own right, and must not be mistaken for what it
    /// carries.
    func testTheGiftwrapItselfIsNotAPrivateReply() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()

        let parent = try Self.publicNote(by: bob)
        let reply = try NIP59.createPrivateReply(Self.replyPost(to: parent, from: alice, content: "wrapped"),
                                                 replyingTo: parent,
                                                 keypair: alice)

        let ndb = try Self.ingest(reply.giftWrapToSelf, unwrappingWith: alice)
        defer { ndb.close() }

        let wrap = try XCTUnwrap(try ndb.lookup_note_and_copy(reply.giftWrapToSelf.id))
        XCTAssertEqual(wrap.kind, 1059)
        XCTAssertFalse(wrap.is_private_reply)
    }

    /// The read paths that never copy a note out of the database borrow it instead, so the predicate
    /// has to answer the same on the borrowed view. A mirror that drifted would be a leak on exactly
    /// the paths that are hottest.
    func testTheBorrowedViewAgreesWithTheOwnedOne() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()

        let parent = try Self.publicNote(by: bob)
        let reply = try NIP59.createPrivateReply(Self.replyPost(to: parent, from: alice, content: "borrowed"),
                                                 replyingTo: parent,
                                                 keypair: alice)
        let ndb = try Self.ingest(reply.giftWrapToSelf, unwrappingWith: alice)
        defer { ndb.close() }

        let rumor = try XCTUnwrap(Self.firstNote(ofKind: .text, in: ndb))
        let borrowed = try NdbNoteLender(ownedNdbNote: rumor).borrow({ $0.is_private_reply })
        XCTAssertTrue(borrowed)

        let wrap = try XCTUnwrap(try ndb.lookup_note_and_copy(reply.giftWrapToSelf.id))
        XCTAssertFalse(try NdbNoteLender(ownedNdbNote: wrap).borrow({ $0.is_private_reply }))
    }

    // MARK: Helpers

    /// A draft that is already a reply to `parent`, the way `build_post` hands one over. The builder
    /// refuses one that is not.
    private static func replyPost(to parent: NostrEvent, from sender: FullKeypair, content: String) -> NostrPost {
        return NostrPost(content: content,
                         tags: nip10_reply_tags(replying_to: parent, keypair: sender.to_keypair(), relayURL: nil))
    }

    private static func publicNote(by author: FullKeypair, content: String = "a public note") throws -> NostrEvent {
        return try XCTUnwrap(NostrEvent(content: content,
                                        keypair: author.to_keypair(),
                                        kind: NostrKind.text.rawValue,
                                        tags: []))
    }

    /// The first note of `kind` in `ndb`, copied out.
    private static func firstNote(ofKind kind: NostrKind, in ndb: Ndb) throws -> NdbNote? {
        let filter = try NdbFilter(from: NostrFilter(kinds: [kind]))
        guard let key = try ndb.query(filters: [filter], maxResults: 10).first else { return nil }
        return try ndb.lookup_note_by_key_and_copy(key)
    }

    /// Ingests `events` and hands back a freshly opened `Ndb` reading the same files.
    ///
    /// Closing the first handle is what makes this deterministic: ingestion is async on the ingester
    /// pool, and `ndb_destroy` drains it.
    private static func seeded(with events: [NostrEvent], unwrappingWith receiver: FullKeypair? = nil) throws -> Ndb {
        let dir = try XCTUnwrap(test_ndb_dir(), "could not create a temp directory")
        // `ndb_process_events` only ingests up to the last newline, so every line needs one.
        let wire = events.compactMap({ encode_json($0) }).map({ "[\"EVENT\",\"s\",\($0)]\n" }).joined()

        do {
            let seed = try XCTUnwrap(Ndb(path: dir))
            if let receiver {
                XCTAssertTrue(seed.add_key(receiver.privkey), "the ingester should accept our key")
            }
            XCTAssertTrue(seed.process_events(wire))
            seed.close()
        }

        return try XCTUnwrap(Ndb(path: dir))
    }

    /// Registers `receiver`'s key, ingests `wrap`, and hands back a database the rumor is known to be
    /// in.
    private static func ingest(_ wrap: NostrEvent, unwrappingWith receiver: FullKeypair) throws -> Ndb {
        return try seeded(with: [wrap], unwrappingWith: receiver)
    }
}
