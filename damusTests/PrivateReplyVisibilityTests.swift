//
//  PrivateReplyVisibilityTests.swift
//  damusTests
//
//  Created by Claude on 2026-09-05.
//

import XCTest
@testable import damus

/// Where a private reply appears, and what it cannot be made to do once it is there.
///
/// **This is the inverse of the assertions phase 9 was carded with**, and deliberately. That card
/// asked for a private reply to be absent from the home timeline, the author's profile, search and
/// reply counts, and present only in its thread. That containment was built, and jb55 rejected it:
/// if the note is visibly locked, hiding it is the wrong trade. So a private reply is drawn wherever
/// a public note is, marked by the audience sentence its reply description carries in place of the
/// public "Replying to @a, @b" line (``ReplyDescription``), and what is withheld is not the note but
/// what can be *done* with it (``NoteActions/available(on:keypair:)``).
///
/// These tests therefore assert the current design rather than a leak. Each one is a tripwire: if a
/// future change starts filtering private replies out of one of these surfaces, that is a decision
/// somebody should make on purpose, and a failing test here is what makes them.
@MainActor
final class PrivateReplyVisibilityTests: XCTestCase {

    /// A real private reply, its parent, and a public reply of the same shape.
    ///
    /// The public reply is the control. Every assertion has to be about *privateness*, not about
    /// something incidental to being a reply, so each surface is checked with both.
    private struct Ingested {
        let parent: NostrEvent
        let rumor: NostrEvent
        let publicReply: NostrEvent
        let sender: FullKeypair
    }

    private func ingestPrivateReply(content: String = "only for you") throws -> Ingested {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let parent = try XCTUnwrap(NostrEvent(content: "a public note", keypair: bob.to_keypair(),
                                              kind: NostrKind.text.rawValue, tags: []))
        let replyTags = nip10_reply_tags(replying_to: parent, keypair: alice.to_keypair(), relayURL: nil)

        let reply = try NIP59.createPrivateReply(NostrPost(content: content, tags: replyTags),
                                                 replyingTo: parent,
                                                 keypair: alice)
        let publicReply = try XCTUnwrap(NostrPost(content: content, tags: replyTags).to_event(keypair: alice))

        let dir = try XCTUnwrap(test_ndb_dir(), "could not create a temp directory")
        let wire = [reply.giftWrapToSelf, parent].compactMap({ encode_json($0) })
            .map({ "[\"EVENT\",\"s\",\($0)]\n" }).joined()
        do {
            let seed = try XCTUnwrap(Ndb(path: dir))
            XCTAssertTrue(seed.add_key(alice.privkey))
            XCTAssertTrue(seed.process_events(wire))
            seed.close()   // draining the ingester pool is what makes the unwrap deterministic
        }
        let ndb = try XCTUnwrap(Ndb(path: dir))
        defer { ndb.close() }

        let filter = try NdbFilter(from: NostrFilter(kinds: [.text]))
        let keys = try ndb.query(filters: [filter], maxResults: 10)
        let notes = try keys.compactMap({ try ndb.lookup_note_by_key_and_copy($0) })
        let rumor = try XCTUnwrap(notes.first(where: { $0.is_private_reply }),
                                  "the fixture has to actually be an unwrapped rumor")

        return Ingested(parent: parent, rumor: rumor, publicReply: publicReply, sender: alice)
    }

    // MARK: The seam every surface shares

    /// `should_show_event` is the filter roughly twenty surfaces run their notes through, and it
    /// treats a private reply as an ordinary note. That single fact is what puts one on all of the
    /// surfaces below, and reversing it here would take it off all of them at once.
    func testTheSharedFilterTreatsAPrivateReplyAsAnOrdinaryNote() throws {
        let f = try ingestPrivateReply()
        let state = test_damus_state

        XCTAssertTrue(should_show_event(state: state, ev: f.rumor))
        XCTAssertTrue(f.rumor.should_show_event, "including the bare property ProfileModel and SearchModel use")
        XCTAssertTrue(should_show_event(state: state, ev: f.publicReply))
    }

    // MARK: The surfaces

    /// The home timeline. Incoherent in one respect worth recording: its contents are defined by a
    /// follow filter, so whether a private reply appears there depends on whether you happen to
    /// follow the sender. Harmless now that it is marked, but it is why the badge and not the
    /// timeline is where the feature's honesty lives.
    func testAPrivateReplyReachesTheHomeTimeline() async throws {
        let f = try ingestPrivateReply()
        let state = make_test_damus_state()
        let home = HomeModel()
        home.damus_state = state

        home.handle_text_event(f.rumor, context: .home)
        home.handle_text_event(f.publicReply, context: .home)

        // The insert is dispatched onto a Task, so wait for it rather than assuming it already ran.
        for _ in 0..<200 {
            if home.events.all_events.contains(where: { $0.id == f.rumor.id }) { break }
            try await Task.sleep(for: .milliseconds(10))
        }

        XCTAssertTrue(home.events.all_events.contains(where: { $0.id == f.rumor.id }),
                      "a private reply is drawn on the home timeline, with its lock")
        XCTAssertTrue(home.events.all_events.contains(where: { $0.id == f.publicReply.id }))
    }

    /// The author's profile timeline.
    func testAPrivateReplyReachesTheProfileTimeline() throws {
        let f = try ingestPrivateReply()
        let state = make_test_damus_state()
        let profile = ProfileModel(pubkey: f.sender.pubkey, damus: state)

        profile.add_event(f.rumor)
        profile.add_event(f.publicReply)

        XCTAssertTrue(profile.events.all_events.contains(where: { $0.id == f.rumor.id }))
        XCTAssertTrue(profile.events.all_events.contains(where: { $0.id == f.publicReply.id }))
    }

    /// **An open question, held here so it cannot change by accident.** A private reply counts into
    /// the *public* reply count on its parent. That is consistent with what the reader sees in the
    /// thread, but the number disagrees with every other client, and it ticks up with no attached
    /// visible-to-others reply — which tells anyone glancing at the screen that a private one
    /// arrived, and roughly when. jb55's decision to drop containment did not settle this.
    func testAPrivateReplyCountsIntoThePublicReplyCount() throws {
        let f = try ingestPrivateReply()
        let counter = ReplyCounter(our_pubkey: f.sender.pubkey)

        counter.count_replies(f.rumor, keypair: f.sender.to_keypair())

        XCTAssertEqual(counter.get_replies(f.parent.id), 1,
                       "current behaviour, and an open question — see the phase 3 card")
    }

    /// The cache's child index, which a reply list drawn from the cache walks.
    func testAPrivateReplyIsInTheCachesChildIndex() throws {
        let f = try ingestPrivateReply()
        let state = make_test_damus_state()

        state.events.insert(f.rumor)
        state.events.add_replies(ev: f.rumor, keypair: f.sender.to_keypair())

        XCTAssertEqual(state.events.child_events(event: f.parent).map(\.id), [f.rumor.id])
    }

    /// **The other open question.** A private reply is plaintext in nostrdb, so it is in the text
    /// index for free and local search returns it. That fell out of dropping containment rather than
    /// being chosen: a search result is a row next to public notes, and it does carry the badge
    /// through `EventShell`, but it arrives with no thread around it to explain itself.
    func testAPrivateReplyIsASearchResult() throws {
        let alice = generate_new_keypair()
        let bob = generate_new_keypair()
        let needle = "zaphodbeeblebrox"
        let parent = try XCTUnwrap(NostrEvent(content: "a public note", keypair: bob.to_keypair(),
                                              kind: NostrKind.text.rawValue, tags: []))
        let replyTags = nip10_reply_tags(replying_to: parent, keypair: alice.to_keypair(), relayURL: nil)
        let priv = try NIP59.createPrivateReply(NostrPost(content: "private \(needle)", tags: replyTags),
                                                replyingTo: parent, keypair: alice)
        let pub = try XCTUnwrap(NostrPost(content: "public \(needle)", tags: replyTags).to_event(keypair: alice))

        let dir = try XCTUnwrap(test_ndb_dir(), "could not create a temp directory")
        let wire = [priv.giftWrapToSelf, pub, parent].compactMap({ encode_json($0) })
            .map({ "[\"EVENT\",\"s\",\($0)]\n" }).joined()
        do {
            let seed = try XCTUnwrap(Ndb(path: dir))
            XCTAssertTrue(seed.add_key(alice.privkey))
            XCTAssertTrue(seed.process_events(wire))
            seed.close()
        }
        let ndb = try XCTUnwrap(Ndb(path: dir))
        defer { ndb.close() }

        let results = try AdvancedSearchEngine.search(AdvancedSearchQuery(keywords: [needle]), in: ndb)
        let contents = try ndb.compact_map_notes(keys: results.keys, { _, note in note.content })

        XCTAssertTrue(contents.contains("public \(needle)"))
        XCTAssertTrue(contents.contains("private \(needle)"),
                      "current behaviour, and an open question — see the phase 3 card")
    }

    /// The thread it was written into. This one was true under the containment design too, and it is
    /// the assertion that keeps the feature from being pointless in either direction.
    func testAPrivateReplyIsPresentInTheThreadItRepliesTo() throws {
        let f = try ingestPrivateReply()
        let state = make_test_damus_state()
        let thread = ThreadModel(event: f.parent, damus_state: state)

        thread.add_event(f.rumor, keypair: state.keypair)

        XCTAssertTrue(thread.sorted_child_events.contains(where: { $0.id == f.rumor.id }))
        XCTAssertEqual(thread.sorted_child_events.first?.content, "only for you",
                       "and it renders its plaintext there")
    }

    // MARK: What being visible costs, and what it does not

    /// The trade the whole design rests on: visible everywhere, and *unrepublishable* everywhere.
    /// Wherever one of the surfaces above draws a private reply, every affordance that would put the
    /// note, or a pointer to it, in front of anyone but its two readers is gone.
    ///
    /// What is left is not "nothing", and the difference is the point. Reply, react and zap survive
    /// because each has a private form to take — the reply and the reaction become rumors in their own
    /// gift wraps, the zap is forced to ``ZapType/priv``. Copy note JSON survives because a pasteboard
    /// has nobody on the other end of it: the reader can already read the note, which is why Copy text
    /// was never withheld either. The rest do not survive: a boost carries the plaintext into a new
    /// signed kind 6, a share hands over an `nevent` that resolves for nobody, a report names a note no
    /// moderator can fetch, and a mutelist is a public record whatever you put in it. So the rule is
    /// not "a private note can do less", it is "a private note cannot be published" — and neither
    /// answering somebody privately nor reading the note yourself is publishing.
    func testEverywhereItIsDrawnItCannotBeRepublished() throws {
        let f = try ingestPrivateReply()
        let actions = NoteActions.available(on: f.rumor, keypair: f.sender.to_keypair())

        XCTAssertEqual(actions, [.reply, .like, .zap, .copyJSON],
                       "the three with a private form plus the one that goes nowhere, and nothing else")
        for (action, why) in [(NoteActions.repost, "a boost embeds the plaintext in a new signed kind 6"),
                              (.share, "an nevent for a rumor is a link nobody else can resolve"),
                              (.broadcast, "Broadcast pushes this exact note to every connected relay"),
                              (.report, "a NIP-56 report names a note no moderator can ever fetch"),
                              (.muteThread, "a mutelist is public, and a rumor's thread id can be its own")] {
            XCTAssertFalse(actions.contains(action), why)
        }

        XCTAssertEqual(NoteActions.available(on: f.publicReply, keypair: f.sender.to_keypair()), .all,
                       "and the public control keeps everything, so this is about privateness")
    }

    /// Copy note JSON, specifically, because it was withheld and is not any more.
    ///
    /// Every other entry in the subtraction above has a recipient — a relay, a moderator, whoever a
    /// link is sent to. This one's destination is the reader's own clipboard, on the device already
    /// displaying the note, behind developer mode, and the JSON it copies cannot be published by
    /// anybody: a rumor's `sig` field is not a signature but the wrap's receiver and id, so no relay
    /// will take the event. Withholding it only ever cost the person holding the key their one way of
    /// diagnosing a note that renders wrong.
    func testTheReaderCanCopyARumorsJSON() throws {
        let f = try ingestPrivateReply()

        XCTAssertTrue(NoteActions.available(on: f.rumor, keypair: f.sender.to_keypair()).contains(.copyJSON),
                      "a pasteboard is not a relay, and Copy text was never withheld either")
        XCTAssertFalse(NoteActions.available(on: f.rumor, keypair: f.sender.to_keypair()).contains(.broadcast),
                       "which is not the same as being allowed to publish it")
    }

    /// And the marker itself: the badge is drawn from the same predicate the surfaces above ignore,
    /// so a private reply on any of them names the one other person who can read it.
    func testAPrivateReplyOnAnySurfaceNamesItsAudience() throws {
        let f = try ingestPrivateReply()

        XCTAssertEqual(private_reply_audience(of: f.rumor), f.parent.pubkey)
        XCTAssertNil(private_reply_audience(of: f.publicReply),
                     "and a public reply gets no badge, however it is tagged")
    }
}
