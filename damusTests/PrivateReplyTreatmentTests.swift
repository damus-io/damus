//
//  PrivateReplyTreatmentTests.swift
//  damusTests
//
//  Created by Claude on 2026-09-05.
//

import XCTest
@testable import damus

/// Covers ``private_reply_audience(of:)`` — the one piece of logic behind the lock treatment, and the
/// answer to the only question a reader has about a private reply: *who else can see this*.
///
/// Getting it wrong in either direction is the whole failure mode of the feature. Naming the wrong
/// person tells the reader their note went somewhere it did not; naming nobody leaves them to guess,
/// and the guess a thread invites is "everyone in it".
///
/// The answer is a function of the note alone and not of who is reading it, so the sender and the
/// recipient are told the same thing about the same note and the composer can say it in advance in
/// the same words. But it is not read off the same *field* at both ends, and that asymmetry is the
/// point of this suite: a note somebody sent us is answered by the gift wrap's receiver, which no
/// sender can influence, and only a note of our own is answered by a `p` tag — because only then is
/// the tag ours. ``testAThreadsPTagsAreNotAnAudience`` is the case that forced that split.
@MainActor
final class PrivateReplyTreatmentTests: XCTestCase {

    /// Ingests `wrap` under `reader`'s key and hands back the rumor nostrdb peeled out of it, exactly
    /// as the app would read it off the database.
    private func ingest(wrap: NostrEvent, as reader: FullKeypair) throws -> NostrEvent {
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
        XCTAssertTrue(rumor.is_private_reply, "the fixture has to actually be an unwrapped rumor")
        return rumor
    }

    /// Builds a real private reply from `sender` to `receiver`'s note **the way damus builds one** and
    /// hands back the rumor as the key in `unwrappingWith` reads it out of nostrdb.
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

        return try ingest(wrap: wrap, as: reader)
    }

    /// Builds a kind-1 rumor **the way another client would** — an ordinary NIP-10 reply with the
    /// thread's `p` tags left on it, rather than damus's single recipient tag — wraps it for `reader`,
    /// and hands back the rumor as `reader` sees it.
    ///
    /// This is not a hypothetical shape. NIP-59 says nothing about what may be wrapped, and a client
    /// that offers "send this reply privately" over an existing thread has no reason to rewrite the
    /// reply's tags on the way in.
    private func ingestedForeignReply(from sender: FullKeypair,
                                      to reader: FullKeypair,
                                      taggingInOrder pubkeys: [Pubkey],
                                      rootAuthor: FullKeypair) throws -> NostrEvent {
        let root = try XCTUnwrap(NostrEvent(content: "the thread", keypair: rootAuthor.to_keypair(),
                                            kind: NostrKind.text.rawValue, tags: []))
        var tags: [[String]] = [["e", root.id.hex(), "", "root"]]
        tags += pubkeys.map({ ["p", $0.hex()] })

        let rumor = NIP59.Rumor(pubkey: sender.pubkey,
                                kind: NostrKind.text.rawValue,
                                tags: tags,
                                content: "sent to you privately",
                                createdAt: UInt32(Date().timeIntervalSince1970))
        let wrap = try NIP59.giftWrap(rumor: rumor, sender: sender, receiver: reader.pubkey)

        return try ingest(wrap: wrap, as: reader)
    }

    /// Reading our own sent reply: the audience is the person we addressed it to, which lives in the
    /// single `p` tag rather than on the note's author, because the author is us.
    ///
    /// This is the one end where a tag is the answer, and it is only safe here: nostrdb copies a
    /// rumor's `pubkey` off the *seal*, a seal is signed, so a rumor naming us as its author can only
    /// have been sealed by our own key.
    func testTheSenderSeesTheirRecipient() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()

        let rumor = try ingestedReply(from: alice, to: bob, unwrappingWith: alice, useReceiverCopy: false)

        XCTAssertEqual(private_reply_audience(of: rumor), bob.pubkey,
                       "our own reply names the person we sent it to")
    }

    /// Reading a reply somebody sent *us*: the audience is us, and the note says so without consulting
    /// a single tag. The gift wrap was addressed to our key — that is the only reason we can read the
    /// note at all — and nostrdb records which key opened it.
    func testAReplyWeReceivedNamesUs() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()

        let rumor = try ingestedReply(from: alice, to: bob, unwrappingWith: bob, useReceiverCopy: true)

        XCTAssertEqual(private_reply_audience(of: rumor), bob.pubkey,
                       "a reply we received was addressed to us, so we are its audience")
        XCTAssertEqual(rumor.pubkey, alice.pubkey,
                       "and the sender is still the sender — the audience is not the author")
    }

    /// The same note read from either end names the same person: bob, who it was addressed to, and not
    /// alice, who wrote it.
    ///
    /// This is the property the shared label rests on. The sentence says "Replying privately to @bob"
    /// to alice and "Replying privately to you" to bob, and both are the same sentence about the same
    /// person; an answer that flipped with the reader would need two sentences and could not be the
    /// one the composer shows before the note exists.
    ///
    /// What it is *not* is the same derivation at both ends, which is what an earlier version of this
    /// test assumed. Alice reads her copy's `p` tag, because her copy's seal is hers; bob reads his
    /// copy's gift-wrap receiver, because a tag on a note he did not write is a claim the sender
    /// chose. They agree here because damus wrote the tag, and only the receiver keeps them agreeing
    /// when somebody else's client wrote it — see ``testAThreadsPTagsAreNotAnAudience``.
    func testTheRecipientIsTheSameOnBothEnds() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()

        let ours = try ingestedReply(from: alice, to: bob, unwrappingWith: alice, useReceiverCopy: false)
        let theirs = try ingestedReply(from: alice, to: bob, unwrappingWith: bob, useReceiverCopy: true)

        XCTAssertEqual(private_reply_audience(of: theirs), bob.pubkey,
                       "a reply we received names who it was addressed to, which is us")
        XCTAssertEqual(private_reply_audience(of: ours), private_reply_audience(of: theirs),
                       "and it is the same answer either way round")
    }

    /// **The bug this suite exists for.** A private reply from a client that wrapped an ordinary
    /// NIP-10 reply — thread `p` tags intact, the root author's key first among them — must still name
    /// *us* as its audience.
    ///
    /// It is the worst possible failure: the sentence is stated as fact, in green, and the person it
    /// names is the one who sent the note. Reading it off the first `p` tag gave exactly that, because
    /// in a thread rooted at the sender's own note the first thread tag *is* the sender.
    func testAThreadsPTagsAreNotAnAudience() throws {
        let vitor = generate_new_keypair()
        let us = generate_new_keypair()
        let carol = generate_new_keypair()

        // A thread rooted at vitor's own note: he is the first `p` tag, as NIP-10 asks.
        let rumor = try ingestedForeignReply(from: vitor, to: us,
                                             taggingInOrder: [vitor.pubkey, carol.pubkey, us.pubkey],
                                             rootAuthor: vitor)

        XCTAssertEqual(private_reply_audience(of: rumor), us.pubkey,
                       "a wrap addressed to us makes us the audience, whatever the sender tagged")
        XCTAssertNotEqual(private_reply_audience(of: rumor), vitor.pubkey,
                          "and never the sender, which is what naming the first p tag produced")
    }

    /// The same shape with our key not tagged at all. There is no `p` tag that could have answered
    /// this, and the gift wrap still does — which is the point of reading the wrap rather than a tag.
    func testAForeignReplyThatDoesNotTagUsStillNamesUs() throws {
        let vitor = generate_new_keypair()
        let us = generate_new_keypair()

        let rumor = try ingestedForeignReply(from: vitor, to: us,
                                             taggingInOrder: [vitor.pubkey],
                                             rootAuthor: vitor)

        XCTAssertEqual(private_reply_audience(of: rumor), us.pubkey,
                       "the wrap was addressed to us, so it reached us, so we are the audience")
    }

    /// Replying privately to your own note: the audience is us, and the label says so as "you".
    ///
    /// The degenerate wrap in ``NIP59/privateEvent(rumor:to:from:)`` — one wrap, addressed to
    /// ourselves — means the author and the receiver are both us here, so this lands on the `p`-tag
    /// branch and the tag names us. Both routes agree, which is the only reason this case is not
    /// ambiguous.
    func testASelfReplyNamesOurselvesAsTheAudience() throws {
        let alice = generate_new_keypair()

        let rumor = try ingestedReply(from: alice, to: alice, unwrappingWith: alice, useReceiverCopy: false)

        XCTAssertEqual(private_reply_audience(of: rumor), alice.pubkey,
                       "a note to self is addressed to us, and the p tag says so")
    }

    /// Our *own* note, wrapped by some other client of ours that kept the thread's `p` tags: we say
    /// nothing rather than name whichever of them came first.
    ///
    /// This is the one case the note cannot answer. The copy we can read is the wrap addressed to
    /// ourselves, so its receiver is us and tells us nothing about who else got one, and a thread's
    /// tags are not an audience here any more than they are on an inbound note. "Replying privately",
    /// unnamed, is the right way to fail a question the reader is trusting us to answer.
    func testOurOwnReplyWithThreadTagsNamesNobody() throws {
        let us = generate_new_keypair()
        let carol = generate_new_keypair()

        let rumor = try ingestedForeignReply(from: us, to: us,
                                             taggingInOrder: [carol.pubkey, us.pubkey],
                                             rootAuthor: carol)

        XCTAssertNil(private_reply_audience(of: rumor),
                     "several p tags on a note of ours is not an audience we can read")
    }

    /// The treatment must never appear on a public note, however it is tagged — that is what keeps the
    /// lock meaning something. `is_private_reply` is nostrdb's rumor flag, which no relay can set.
    func testAPublicNoteHasNoAudience() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let impostor = try XCTUnwrap(NostrEvent(
            content: "this is not private, whatever it says",
            keypair: alice.to_keypair(),
            kind: NostrKind.text.rawValue,
            tags: [["p", bob.pubkey.hex()], ["private", ""]]
        ))

        XCTAssertNil(private_reply_audience(of: impostor),
                     "nobody can publish themselves a lock badge in someone else's thread")
    }
}
