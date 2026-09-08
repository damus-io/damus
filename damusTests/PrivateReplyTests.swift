//
//  PrivateReplyTests.swift
//  damusTests
//
//  Created by Claude on 2026-09-05.
//

import XCTest
@testable import damus

/// Covers the private reply send path: ``NIP59/createPrivateReply(_:replyingTo:keypair:createdAt:)``
/// and the ``NIP59`` layers under it. Pure construction — no nostrdb, no network, no UI.
///
/// The two load-bearing properties here are that the reply tags are *byte-identical* to the public
/// reply the same draft would have produced — that is what makes a private reply parse as a reply to
/// the right note in any client that can open it — and that the `p` tags are *not*: on a private
/// reply the `p` tags are the audience, not a mention list, so exactly one survives.
final class PrivateReplyTests: XCTestCase {

    /// A public note by `author` to reply to.
    private func makeParent(by author: FullKeypair, content: String = "a public note") -> NostrEvent {
        return NostrEvent(content: content, keypair: author.to_keypair(), kind: NostrKind.text.rawValue, tags: [])!
    }

    /// A draft that is already a reply to `parent`, the way `build_post` hands one over.
    ///
    /// The builder does not invent reply tags — it cannot, since they need relay hints only the async
    /// post path can look up — so a fixture that skipped this would be testing a private *note* with
    /// no parent rather than a private reply.
    private func replyPost(to parent: NostrEvent, from sender: FullKeypair, content: String) -> NostrPost {
        return NostrPost(content: content,
                         tags: nip10_reply_tags(replying_to: parent, keypair: sender.to_keypair(), relayURL: nil))
    }

    // MARK: The rumor

    /// A private reply is a kind-1 note. That is what makes it sit where a reply sits, both in our own
    /// thread view and in any other client that can open the wrap.
    func testTheRumorIsAnOrdinaryKindOneNote() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let parent = makeParent(by: bob)

        let reply = try NIP59.createPrivateReply(replyPost(to: parent, from: alice, content: "just between us"),
                                                 replyingTo: parent,
                                                 keypair: alice)

        XCTAssertEqual(reply.rumor.kind, NostrKind.text.rawValue)
        XCTAssertEqual(reply.rumor.content, "just between us")
        XCTAssertEqual(reply.rumor.pubkey, alice.pubkey, "the rumor names the real sender; it never leaves the seal")
    }

    /// The rumor's `created_at` is the real send time, unfuzzed. It is inside two layers of
    /// encryption, so nobody but the two parties ever sees it, and it is what the thread orders by —
    /// fuzzing it would scatter a private reply to the wrong place in the conversation.
    func testTheRumorKeepsTheRealSendTime() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let sentAt: UInt32 = 1_900_000_000

        let parent = makeParent(by: bob)
        let reply = try NIP59.createPrivateReply(replyPost(to: parent, from: alice, content: "when?"),
                                                 replyingTo: parent,
                                                 keypair: alice,
                                                 createdAt: sentAt)

        XCTAssertEqual(reply.rumor.created_at, sentAt)
        for wrap in reply.giftWraps {
            XCTAssertNotEqual(wrap.created_at, sentAt, "the wrap's timestamp is deliberately noise")
            XCTAssertLessThanOrEqual(wrap.created_at, UInt32(Date().timeIntervalSince1970),
                                     "fuzzing only ever moves a timestamp into the past")
        }
    }

    /// A rumor is unsigned by construction, which is what stops it being mistaken for a publishable
    /// event: it is not a ``NostrEvent`` at all, and its JSON has no `sig` field for a relay to check.
    func testTheRumorIsUnsignedAndUnpublishable() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()

        let parent = makeParent(by: bob)
        let reply = try NIP59.createPrivateReply(replyPost(to: parent, from: alice, content: "unsigned"),
                                                 replyingTo: parent,
                                                 keypair: alice)

        let json = try XCTUnwrap(reply.rumor.json)
        XCTAssertFalse(json.contains("\"sig\""), "a rumor has no signature — that is the point of one")
    }

    // MARK: Reply tags

    /// The whole reason a private reply is a kind 1 with NIP-10 tags: it must parse as a reply to
    /// exactly the note the public reply would have pointed at, tag for tag.
    func testReplyTagsAreIdenticalToThePublicReplyItCouldHaveBeen() async throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let parent = makeParent(by: bob)

        let post = await build_post(state: test_damus_state,
                                    post: .init(string: "same tags either way"),
                                    action: .replying_to(parent),
                                    uploadedMedias: [],
                                    pubkeys: [])
        let publicReply = try XCTUnwrap(post.to_event(keypair: alice))
        let privateReply = try NIP59.createPrivateReply(post, replyingTo: parent, keypair: alice)

        let publicETags = publicReply.tags.map({ $0.strings() }).filter({ $0.first == "e" })
        let privateETags = privateReply.rumor.tags.filter({ $0.first == "e" })

        XCTAssertFalse(publicETags.isEmpty, "the fixture has to actually be a reply for this to mean anything")
        XCTAssertEqual(privateETags, publicETags, "byte-identical NIP-10 reply tags")
        XCTAssertEqual(privateReply.rumor.content, publicReply.content, "and the same rendered content")
    }

    /// The `p` tags of a private reply are its **audience**, not a mention list. Everything the public
    /// path would have carried — the other thread participants, anyone @-mentioned in the text — is
    /// dropped, and exactly one goes back: the author of the note being replied to.
    ///
    /// A stray `p` tag here would either widen the audience in another client's eyes or promise a
    /// delivery we never make, since we only ever publish the one wrap.
    func testItAddressesTheParentsAuthorAndNobodyElse() async throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let charlie = generate_new_keypair()
        let parent = makeParent(by: bob)

        // A draft that the public path would have `p`-tagged three people on.
        let post = await build_post(state: test_damus_state,
                                    post: .init(string: "hello all"),
                                    action: .replying_to(parent),
                                    uploadedMedias: [],
                                    pubkeys: [charlie.pubkey, alice.pubkey])
        let publicReply = try XCTUnwrap(post.to_event(keypair: alice))
        XCTAssertGreaterThan(publicReply.tags.map({ $0.strings() }).filter({ $0.first == "p" }).count, 1,
                             "the public reply has to carry several p tags for this test to be testing anything")

        let privateReply = try NIP59.createPrivateReply(post, replyingTo: parent, keypair: alice)
        let pTags = privateReply.rumor.tags.filter({ $0.first == "p" })

        XCTAssertEqual(pTags, [["p", bob.pubkey.hex()]], "exactly one p tag, naming the parent's author")
    }

    /// No marker tag, and nothing else decorative: the rumor carries the reply tags, the audience, and
    /// whatever the draft itself produced. A "do not re-broadcast me" marker was considered and
    /// dropped — a rumor is unsigned, so no relay would accept one however it is tagged, and a client
    /// determined to leak the contents would re-sign them as a note of its own, which no tag stops.
    func testTheRumorCarriesNothingBeyondTheReplyAndItsAudience() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let parent = makeParent(by: bob)

        let reply = try NIP59.createPrivateReply(replyPost(to: parent, from: alice, content: "plain"),
                                                 replyingTo: parent,
                                                 keypair: alice)

        XCTAssertEqual(reply.rumor.tags, [
            ["e", parent.id.hex(), "", "root", bob.pubkey.hex()],
            ["p", bob.pubkey.hex()],
        ])
    }

    /// The builder cannot invent reply tags — they need relay hints only the async post path can look
    /// up — so it refuses a draft that is not already a reply to the parent rather than wrapping a
    /// note with no parent at all. A private reply that lost its `e` tag is not a slightly worse
    /// reply: it appears in no thread, and neither party can place it.
    func testADraftThatIsNotAReplyToTheParentIsRefused() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let parent = makeParent(by: bob)
        let someoneElsesNote = makeParent(by: bob, content: "a different note")

        XCTAssertThrowsError(try NIP59.createPrivateReply(NostrPost(content: "no reply tags at all"),
                                                          replyingTo: parent,
                                                          keypair: alice))

        XCTAssertThrowsError(try NIP59.createPrivateReply(replyPost(to: someoneElsesNote, from: alice, content: "wrong parent"),
                                                          replyingTo: parent,
                                                          keypair: alice),
                             "reply tags naming a different note are not reply tags for this one")
    }

    // MARK: The wraps

    /// Two wraps, one per copy, and *only* wraps: the reply itself never gets published.
    func testASentPrivateReplyIsTwoGiftwrapsAndNothingElse() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()

        let parent = makeParent(by: bob)
        let reply = try NIP59.createPrivateReply(replyPost(to: parent, from: alice, content: "hi bob"),
                                                 replyingTo: parent,
                                                 keypair: alice)

        XCTAssertEqual(reply.giftWraps.count, 2)
        XCTAssertEqual(reply.giftWraps.map({ $0.kind }), [1059, 1059],
                       "only the kind-1059 wraps are publishable")
        XCTAssertEqual(Set(reply.giftWraps.map({ $0.referenced_pubkeys.first })), [bob.pubkey, alice.pubkey],
                       "one wrap addressed to the parent's author, one to ourselves")
        XCTAssertEqual(reply.giftWrapToSelf.referenced_pubkeys.first, alice.pubkey)
        XCTAssertEqual(reply.giftWrapToReceiver?.referenced_pubkeys.first, bob.pubkey)
        XCTAssertTrue(reply.giftWraps.contains(where: { $0.id == reply.giftWrapToSelf.id }),
                      "the copy we ingest locally has to be one of the ones we publish")

        for wrap in reply.giftWraps {
            XCTAssertTrue(wrap.verify(), "a wrap is signed by its ephemeral key")
            XCTAssertFalse(wrap.is_rumor)
        }
    }

    /// Reusing an ephemeral key across the pair would prove to a relay operator that whoever sent one
    /// wrap sent the other — the exact correlation the wrap exists to destroy. This is the kind of
    /// thing a refactor reintroduces silently, so it gets its own assertion.
    func testTheTwoWrapsAreNotLinkable() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()

        let parent = makeParent(by: bob)
        let reply = try NIP59.createPrivateReply(replyPost(to: parent, from: alice, content: "unlinkable"),
                                                 replyingTo: parent,
                                                 keypair: alice)
        let (first, second) = (reply.giftWraps[0], reply.giftWraps[1])

        XCTAssertNotEqual(first.pubkey, second.pubkey, "each wrap gets its own throwaway signing key")
        XCTAssertNotEqual(first.pubkey, alice.pubkey, "our own pubkey must never sign a wrap")
        XCTAssertNotEqual(second.pubkey, alice.pubkey)
        XCTAssertNotEqual(first.id, second.id)
        XCTAssertNotEqual(first.content, second.content, "each wrap encrypts its own seal")
    }

    /// Replying to your own note is the degenerate case: the recipient's copy and our own copy are the
    /// same copy, so a second wrap would put the message on the relay twice for nothing.
    func testASelfReplyIsASingleWrap() throws {
        let alice = generate_new_keypair()
        let ownNote = makeParent(by: alice)

        let reply = try NIP59.createPrivateReply(replyPost(to: ownNote, from: alice, content: "note to self"),
                                                 replyingTo: ownNote,
                                                 keypair: alice)

        XCTAssertEqual(reply.giftWraps.count, 1)
        XCTAssertEqual(reply.giftWrapToSelf.id, reply.giftWraps[0].id)
        XCTAssertNil(reply.giftWrapToReceiver)
        XCTAssertEqual(reply.rumor.tags.filter({ $0.first == "p" }), [["p", alice.pubkey.hex()]])
    }

    /// The one thing that must never be true of anything we publish.
    func testNoWrapCarriesThePlaintext() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let secret = "the-quick-brown-fox-jumps-over-1e9d4f"

        let parent = makeParent(by: bob)
        let reply = try NIP59.createPrivateReply(replyPost(to: parent, from: alice, content: secret),
                                                 replyingTo: parent,
                                                 keypair: alice)

        for wrap in reply.giftWraps {
            let json = try XCTUnwrap(encode_json(wrap))
            XCTAssertFalse(json.contains(secret), "the plaintext must not survive into a published wrap")
            XCTAssertNotEqual(wrap.pubkey, alice.pubkey, "a wrap is signed by a throwaway key, never by us")
        }

        // Our own pubkey appears on the self-wrap, unavoidably, as the `p` tag naming who it is for —
        // that is the same tag every DM to oneself carries and says nothing about who sent it. On the
        // wrap that actually goes to the other party it must not appear at all.
        let toBob = try XCTUnwrap(encode_json(try XCTUnwrap(reply.giftWrapToReceiver)))
        XCTAssertFalse(toBob.contains(alice.pubkey.hex()), "the sender's pubkey never leaves the seal")
    }
}
