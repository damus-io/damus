//
//  PrivateReplySendTests.swift
//  damusTests
//
//  Created by Claude on 2026-09-05.
//

import XCTest
@testable import damus

/// Covers the send half of a private reply: ``send_private_reply(_:replyingTo:keypair:damus_state:)``,
/// and the composer conditions that decide whether the lock is offered at all.
///
/// The two claims worth testing here are opposites of each other. One is that the reply *does* come
/// back — a private reply that never reaches the sender's own thread is a message they can never
/// read again, since the only other copy is encrypted to somebody else. The other is that nothing
/// *else* goes anywhere: the rumor is the message in the clear, and the whole feature is the promise
/// that it never leaves the wrap.
///
/// Both run against a real `DamusState` over a real nostrdb, through the real publish path, because
/// neither claim can be checked on the values the builder returns. Whether the rumor comes back is a
/// question for nostrdb's unwrapper, and what reaches a relay is a question for `PostBox`.
final class PrivateReplySendTests: XCTestCase {

    // MARK: What comes back

    /// The sender's own copy: a private reply typed in the composer has to appear in the thread it
    /// answers, on the sending device, through the ordinary read path.
    ///
    /// Nothing here inserts the reply optimistically. Only the wrap addressed to us is handed to
    /// nostrdb; the rumor that comes out the other side is what the thread's own `kinds: [1]` query
    /// finds, and what `ThreadModel` sorts into place.
    @MainActor
    func testASentPrivateReplyComesBackThroughTheThreadsOwnQuery() async throws {
        let state = try private_reply_state()
        let bob = generate_new_keypair()
        let parent = try seed_parent_note(by: bob, in: state)

        let sent = await send_private_reply(reply_post(to: parent, from: test_keypair_full, content: "only for you, bob"),
                                            replyingTo: parent,
                                            keypair: test_keypair_full,
                                            damus_state: state)
        XCTAssertTrue(sent)

        // The thread's own filter, verbatim from `ThreadModel.subscribe`: replies to the parent, kind
        // 1. If the rumor did not satisfy this, no amount of view code would put it in the thread.
        var thread_filter = NostrFilter()
        thread_filter.referenced_ids = [parent.id]
        thread_filter.kinds = [.text]

        let reply = try poll_for_note(matching: thread_filter, in: state)
        XCTAssertTrue(reply.is_private_reply, "it comes back marked, which is what draws the lock")
        XCTAssertEqual(reply.content, "only for you, bob")
        XCTAssertEqual(reply.pubkey, state.pubkey, "nostrdb copies the real sender off the seal")
        XCTAssertEqual(reply.thread_reply()?.reply.note_id, parent.id)

        // And the model the thread view actually renders puts it under the parent.
        let thread = ThreadModel(event: parent, damus_state: state)
        thread.add_event(reply, keypair: state.keypair)
        XCTAssertTrue(thread.sorted_child_events.contains(where: { $0.id == reply.id }),
                      "a private reply belongs in the thread it answers")
    }

    /// Replying to your own note is the one-wrap case, and it still has to come back — the copy for
    /// the recipient and the copy for us are the same copy, so losing it loses the message entirely.
    @MainActor
    func testAPrivateReplyToOurOwnNoteComesBackToo() async throws {
        let state = try private_reply_state()
        let parent = try seed_parent_note(by: test_keypair_full, in: state)

        let sent = await send_private_reply(reply_post(to: parent, from: test_keypair_full, content: "a note to self"),
                                            replyingTo: parent,
                                            keypair: test_keypair_full,
                                            damus_state: state)
        XCTAssertTrue(sent)

        var thread_filter = NostrFilter()
        thread_filter.referenced_ids = [parent.id]
        thread_filter.kinds = [.text]
        let reply = try poll_for_note(matching: thread_filter, in: state)
        XCTAssertTrue(reply.is_private_reply)
        XCTAssertEqual(reply.content, "a note to self")

        let queued = await state.nostrNetwork.postbox.events
        XCTAssertEqual(queued.count, 1, "one wrap, because there is only one addressee")
    }


    // MARK: What goes on the wire

    /// The claim the whole feature rests on: the only things handed to the relay path are the two
    /// kind-1059 wraps. Not the reply, not the parent, not a re-broadcast of anything the reply
    /// references.
    @MainActor
    func testNothingButTheTwoGiftWrapsIsHandedToTheRelayPath() async throws {
        let state = try private_reply_state()
        let bob = generate_new_keypair()
        let parent = try seed_parent_note(by: bob, in: state)

        let sent = await send_private_reply(reply_post(to: parent, from: test_keypair_full, content: "the secret"),
                                            replyingTo: parent,
                                            keypair: test_keypair_full,
                                            damus_state: state)
        XCTAssertTrue(sent)

        let queued = await state.nostrNetwork.postbox.events
        XCTAssertEqual(queued.count, 2, "one wrap per addressee, and nothing else")
        XCTAssertEqual(Set(queued.values.map({ $0.event.kind })), [1059])

        for posted in queued.values {
            XCTAssertFalse(posted.event.is_rumor)
            XCTAssertTrue(posted.event.verify(), "a wrap is signed by its own ephemeral key")
            XCTAssertNotEqual(posted.event.pubkey, state.pubkey, "our own key must never sign a wrap")
            XCTAssertFalse(posted.event.content.contains("the secret"),
                           "the reply text is inside the encryption, not beside it")
        }

        // The parent is deliberately *not* re-broadcast. The public post path helps resolve a reply's
        // references by republishing them; doing that here would put the parent on a relay at the same
        // moment as two wraps, which is most of the way to saying who they are for.
        XCTAssertNil(queued[parent.id], "the note being replied to is not republished alongside the wraps")
    }

    /// The negative case for the builder's one refusal, driven through the send path. A composer that
    /// hands over the wrong `PostAction` produces a post whose reply tags name a different note; that
    /// must send nothing at all rather than wrap a message into a thread neither party can place.
    @MainActor
    func testAPostThatIsNotAReplyToTheParentSendsNothing() async throws {
        let state = try private_reply_state()
        let bob = generate_new_keypair()
        let parent = try seed_parent_note(by: bob, in: state)
        let unrelated = try seed_parent_note(by: bob, content: "some other note", in: state)

        let sent = await send_private_reply(reply_post(to: unrelated, from: test_keypair_full, content: "misaddressed"),
                                            replyingTo: parent,
                                            keypair: test_keypair_full,
                                            damus_state: state)

        XCTAssertFalse(sent, "the composer stays open with the user's text in it")
        let queued = await state.nostrNetwork.postbox.events
        XCTAssertTrue(queued.isEmpty, "a refused build publishes nothing")
    }


    // MARK: When the composer offers the lock

    /// The seal has to be signed by us, so a pubkey-only login cannot make a private reply at all.
    /// The composer answers that before offering the affordance rather than discovering it at send
    /// time — a lock that cannot send is worse than no lock.
    @MainActor
    func testTheLockIsNotOfferedToAPubkeyOnlyLogin() throws {
        let watch_only = make_test_damus_state(keypair: Keypair(pubkey: test_pubkey, privkey: nil))
        let parent = try XCTUnwrap(NostrEvent(content: "a public note", keypair: test_keypair, kind: 1, tags: []))

        let composer = PostView(action: .replying_to(parent), damus_state: watch_only)

        XCTAssertNil(composer.private_reply_recipient)
        XCTAssertFalse(composer.can_reply_privately)
        XCTAssertFalse(composer.sending_privately)
    }

    /// With a full keypair, replying offers the lock and names the parent's author as the audience.
    @MainActor
    func testTheLockIsOfferedWhenReplyingWithAFullKeypair() throws {
        let state = make_test_damus_state()
        let bob = generate_new_keypair()
        let parent = try XCTUnwrap(NostrEvent(content: "bob says something", keypair: bob.to_keypair(), kind: 1, tags: []))

        let composer = PostView(action: .replying_to(parent), damus_state: state)

        XCTAssertEqual(composer.private_reply_recipient, bob.pubkey, "the audience is the parent's author")
        XCTAssertTrue(composer.can_reply_privately)
        XCTAssertFalse(composer.sending_privately, "and the lock starts off — a reply is public unless asked otherwise")
    }

    /// A private *top-level* note is meaningless: there is no parent author to address it to. So the
    /// lock exists only when replying, in every other `PostAction`.
    @MainActor
    func testTheLockIsNotOfferedOutsideAReply() throws {
        let state = make_test_damus_state()
        let quoted = try XCTUnwrap(NostrEvent(content: "quote me", keypair: test_keypair, kind: 1, tags: []))

        for action in [PostAction.posting(.none), .quoting(quoted)] {
            let composer = PostView(action: action, damus_state: state)
            XCTAssertNil(composer.private_reply_recipient, "no lock for \(action)")
            XCTAssertFalse(composer.can_reply_privately)
        }
    }


    // MARK: Helpers

    /// A `DamusState` on its own database, logged in as the shared test identity, with its key
    /// registered so nostrdb's ingester can open the wrap we address to ourselves.
    ///
    /// Without the key the wrap is stored as an un-openable kind 1059 and the reply never comes back
    /// — which is exactly the failure the first test here is checking for, so it must not be faked.
    @MainActor
    private func private_reply_state() throws -> DamusState {
        let state = make_test_damus_state()
        XCTAssertTrue(state.ndb.add_key(test_keypair_full.privkey),
                      "the ingester needs our key to unwrap our own copy")
        return state
    }

    /// A reply draft as `build_post` hands one over: already carrying the NIP-10 tags naming `parent`.
    private func reply_post(to parent: NostrEvent, from sender: FullKeypair, content: String) -> NostrPost {
        return NostrPost(content: content,
                         tags: nip10_reply_tags(replying_to: parent, keypair: sender.to_keypair(), relayURL: nil))
    }

    /// Puts a public note in `state`'s database and waits for it to be readable.
    @MainActor
    @discardableResult
    private func seed_parent_note(by author: FullKeypair, content: String = "a public note", in state: DamusState) throws -> NostrEvent {
        let note = try XCTUnwrap(NostrEvent(content: content, keypair: author.to_keypair(), kind: 1, tags: []))
        try state.ndb.add(event: note)
        try poll(until: { (try? state.ndb.lookup_note_and_copy(note.id)) != nil })
        return note
    }

    /// The first note matching `filter`, once nostrdb has one.
    ///
    /// Ingestion — and the unwrapping that produces the rumor — happens on nostrdb's own threadpool,
    /// so this waits for the result rather than assuming the send already produced it.
    @MainActor
    private func poll_for_note(matching filter: NostrFilter, in state: DamusState) throws -> NdbNote {
        let ndb_filter = try NdbFilter(from: filter)
        var found: NdbNote? = nil
        try poll(until: {
            guard let key = try? state.ndb.query(filters: [ndb_filter], maxResults: 10).first else { return false }
            found = try? state.ndb.lookup_note_by_key_and_copy(key)
            return found != nil
        })
        return try XCTUnwrap(found, "nostrdb never produced the reply")
    }

    /// Polls `condition` for up to five seconds.
    private func poll(until condition: () throws -> Bool) throws {
        for _ in 0..<200 {
            if try condition() { return }
            usleep(25_000)
        }
        XCTFail("nostrdb never produced what the test was waiting for")
    }
}
