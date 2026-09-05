//
//  PrivateReplyTreatmentTests.swift
//  damusTests
//
//  Created by Claude on 2026-09-05.
//

import XCTest
@testable import damus

/// Covers ``private_reply_counterparty(event:our_pubkey:)`` — the one piece of logic behind the lock
/// treatment, and the answer to the only question a reader has about a private reply: *who else can
/// see this*.
///
/// Getting it wrong in either direction is the whole failure mode of the feature. Naming the wrong
/// person tells the reader their note went somewhere it did not; naming nobody leaves them to guess,
/// and the guess a thread invites is "everyone in it".
@MainActor
final class PrivateReplyTreatmentTests: XCTestCase {

    /// Builds a real private reply from `sender` to `receiver`'s note and hands back the rumor as the
    /// key in `unwrappingWith` reads it out of nostrdb.
    private func ingestedReply(from sender: FullKeypair,
                               to receiver: FullKeypair,
                               unwrappingWith reader: FullKeypair,
                               useReceiverCopy: Bool) throws -> NostrEvent {
        let parent = try XCTUnwrap(NostrEvent(content: "a public note", keypair: receiver.to_keypair(),
                                              kind: NostrKind.text.rawValue, tags: []))
        let tags = nip10_reply_tags(replying_to: parent, keypair: sender.to_keypair(), relayURL: nil)
        let reply = try NIP59.createPrivateReply(NostrPost(content: "between us", tags: tags),
                                                 replyingTo: parent,
                                                 keypair: sender)
        let wrap = useReceiverCopy ? try XCTUnwrap(reply.giftWrapToReceiver) : reply.giftWrapToSelf

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

    /// Reading our own sent reply: the other person is the one we addressed it to, which lives in the
    /// single `p` tag rather than on the note's author, because the author is us.
    func testTheSenderSeesTheirRecipient() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()

        let rumor = try ingestedReply(from: alice, to: bob, unwrappingWith: alice, useReceiverCopy: false)

        XCTAssertEqual(private_reply_counterparty(event: rumor, our_pubkey: alice.pubkey), bob.pubkey,
                       "our own reply names the person we sent it to")
    }

    /// Reading a reply somebody sent us: the other person is its author.
    func testTheRecipientSeesTheSender() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()

        let rumor = try ingestedReply(from: alice, to: bob, unwrappingWith: bob, useReceiverCopy: true)

        XCTAssertEqual(private_reply_counterparty(event: rumor, our_pubkey: bob.pubkey), alice.pubkey,
                       "a reply we received names whoever sent it")
    }

    /// Replying privately to your own note: there is no third party, so there is nobody to name and
    /// the badge falls back to "only you". Naming ourselves would be worse than saying nothing.
    func testASelfReplyNamesOurselvesAsTheAudience() throws {
        let alice = generate_new_keypair()

        let rumor = try ingestedReply(from: alice, to: alice, unwrappingWith: alice, useReceiverCopy: false)

        XCTAssertEqual(private_reply_counterparty(event: rumor, our_pubkey: alice.pubkey), alice.pubkey,
                       "a note to self is addressed to us, and the p tag says so")
    }

    /// The treatment must never appear on a public note, however it is tagged — that is what keeps the
    /// lock meaning something. `is_private_reply` is nostrdb's rumor flag, which no relay can set.
    func testAPublicNoteHasNoCounterparty() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let impostor = try XCTUnwrap(NostrEvent(
            content: "this is not private, whatever it says",
            keypair: alice.to_keypair(),
            kind: NostrKind.text.rawValue,
            tags: [["p", bob.pubkey.hex()], ["private", ""]]
        ))

        XCTAssertNil(private_reply_counterparty(event: impostor, our_pubkey: bob.pubkey),
                     "nobody can publish themselves a lock badge in someone else's thread")
    }
}
