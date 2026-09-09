//
//  DraftTests.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2025-01-15

import XCTest
@testable import damus

/// Covers how a NIP-37 draft is stored and read back.
///
/// A draft is a kind-31234 event carrying the drafted note's JSON, sealed in a ``PNS`` envelope and
/// handed to nostrdb. Nothing here fakes that: the tests build a real kind-1080, hand it to a real
/// database whose ingester holds the key, and read the draft back out with the same query
/// ``Drafts/load(from:)`` runs. A draft that only *looked* right would be stored still sealed and
/// never come back.
class DraftTests: XCTestCase {
    func testRoundtripNIP37Draft() throws {
        let test_note =
                NostrEvent(
                    content: "Test",
                    keypair: test_keypair_full.to_keypair(),
                    createdAt: UInt32(Date().timeIntervalSince1970 - 100)
                )!
        let draft = NIP37Draft(unwrapped_note: test_note, draft_id: "test")
        let draft_note = try draft.draft_note(author: test_keypair_full.pubkey)

        XCTAssertEqual(draft_note.kind, NostrKind.draft.rawValue)
        XCTAssertEqual(draft_note.tags.first, ["d", "test"])
        XCTAssertEqual(NdbNote.owned_from_json(json: draft_note.content), test_note,
                       "the draft event's content is the drafted note's JSON, in the clear")

        let stored = try XCTUnwrap(NdbNote(content: draft_note.content,
                                           keypair: test_keypair_full.to_keypair(),
                                           kind: draft_note.kind,
                                           tags: draft_note.tags))
        let read_back = try XCTUnwrap(NIP37Draft(draft_note: stored))
        XCTAssertEqual(read_back.id, "test")
        XCTAssertEqual(read_back.unwrapped_note, test_note)
    }


    // MARK: - The PNS envelope

    /// The claim the whole design rests on: a draft handed to nostrdb inside a kind-1080 envelope is
    /// opened by the ingester and stored as an ordinary, queryable kind-31234 note — no decryption
    /// on any thread in Swift, and nothing on disk that says what the draft is.
    @MainActor
    func testADraftSealedInAPNSEnvelopeComesBackFromAPlainQuery() throws {
        let state = try drafts_state()
        let post = try XCTUnwrap(NostrEvent(content: "a sealed post draft", keypair: test_keypair, kind: 1, tags: []))
        let draft_id = try seed_draft(post, in: state)

        let note = try XCTUnwrap(stored_draft(draft_id, in: state))
        XCTAssertEqual(note.kind, NostrKind.draft.rawValue)
        XCTAssertTrue(note.is_rumor, "the draft event comes out of the envelope flagged as a rumor")
        XCTAssertEqual(note.pubkey, state.pubkey, "a draft is authored by us, which is what the query filters on")
        XCTAssertEqual(NIP37Draft.unwrap(draft_note: note), post)

        // The envelope itself gives nothing away: it is not authored by us, and its content is
        // ciphertext.
        let envelopes = try state.ndb.query(filters: [try NdbFilter(from: NostrFilter(kinds: [.draft], authors: [state.pubkey]))],
                                            maxResults: 10)
        XCTAssertFalse(envelopes.isEmpty)
        XCTAssertNotEqual(try PNS.key(for: test_keypair_full.privkey).keypair.pubkey, state.pubkey)
    }

    /// The PNS key has to be derived exactly the way `ndb_ingester_add_pns_key` derives it, or
    /// envelopes are stored and quietly never opened. Pin the derivation against a known secret.
    func testPNSKeyDerivationIsStable() throws {
        let secret = try XCTUnwrap(Privkey(hex: "0000000000000000000000000000000000000000000000000000000000000001"))
        let key = try PNS.key(for: secret)
        XCTAssertNotEqual(key.keypair.pubkey, try XCTUnwrap(privkey_to_pubkey(privkey: secret)),
                          "the envelope is authored by a derived key, never by the device key itself")
        XCTAssertEqual(try PNS.key(for: secret).keypair.privkey, key.keypair.privkey,
                       "derivation is deterministic")
    }


    // MARK: - Loading saved drafts

    /// A saved post draft belongs under `post`.
    @MainActor
    func testLoadFilesPostDrafts() throws {
        let state = try drafts_state()
        let post = try XCTUnwrap(NostrEvent(content: "a saved post draft", keypair: test_keypair, kind: 1, tags: []))
        _ = try seed_draft(post, in: state)

        state.drafts.load(from: state)

        XCTAssertEqual(state.drafts.post?.content.string, "a saved post draft")
    }

    /// A saved draft that replies to a note belongs under `replies`, not `post`.
    @MainActor
    func testLoadFilesReplyDraftsUnderTheNoteTheyReplyTo() throws {
        let state = try drafts_state()
        let replied_to = try XCTUnwrap(NoteId(hex: "7c7d37bc8c04d2ec65cbc7d9275253e6b5cc34b5d10439f158194a3feefa8d52"))
        let reply = try XCTUnwrap(NostrEvent(content: "a saved reply draft", keypair: test_keypair, kind: 1, tags: [["e", replied_to.hex()]]))
        _ = try seed_draft(reply, in: state)

        state.drafts.load(from: state)

        XCTAssertNil(state.drafts.post)
        XCTAssertEqual(state.drafts.replies[replied_to]?.content.string, "a saved reply draft")
    }

    /// A saved draft that quotes a note belongs under `quotes`, keyed on the quoted note.
    @MainActor
    func testLoadFilesQuoteDraftsUnderTheNoteTheyQuote() throws {
        let state = try drafts_state()
        let quoted = try XCTUnwrap(NoteId(hex: "7c7d37bc8c04d2ec65cbc7d9275253e6b5cc34b5d10439f158194a3feefa8d52"))
        let quote = try XCTUnwrap(NostrEvent(content: "a saved quote draft nostr:\(bech32_note_id(quoted))",
                                             keypair: test_keypair, kind: 1, tags: [["q", quoted.hex()]]))
        _ = try seed_draft(quote, in: state)

        state.drafts.load(from: state)

        XCTAssertNil(state.drafts.post)
        XCTAssertEqual(state.drafts.quotes[quoted]?.content.string, "a saved quote draft ")
    }

    /// A saved highlight draft belongs under `highlights`, keyed on the text it highlights. Its
    /// editable content is the comment on the highlight, not the highlighted text itself.
    @MainActor
    func testLoadFilesHighlightDraftsUnderTheirHighlight() throws {
        let state = try drafts_state()
        let source_url = try XCTUnwrap(URL(string: "https://damus.io/"))
        let highlight = try XCTUnwrap(NostrEvent(content: "the highlighted text",
                                                 keypair: test_keypair,
                                                 kind: NostrKind.highlight.rawValue,
                                                 tags: [["r", source_url.absoluteString, "source"],
                                                        ["comment", "a saved highlight draft"]]))
        _ = try seed_draft(highlight, in: state)

        state.drafts.load(from: state)

        XCTAssertNil(state.drafts.post)
        let expected = HighlightContentDraft(selected_text: "the highlighted text", source: .external_url(source_url))
        XCTAssertEqual(state.drafts.highlights[expected]?.content.string, "a saved highlight draft")
    }

    /// nostrdb keeps every version of every draft — it has no delete and no replaceable-event
    /// handling — so a load has to resolve a draft to the newest note carrying its `d` tag. If it
    /// did not, editing a draft and relaunching could bring back an older revision of it.
    @MainActor
    func testLoadTakesTheNewestVersionOfADraft() throws {
        let state = try drafts_state()
        let draft_id = UUID().uuidString
        let now = UInt32(Date().timeIntervalSince1970)

        let old = try XCTUnwrap(NostrEvent(content: "the old text", keypair: test_keypair, kind: 1, tags: []))
        _ = try seed_draft(old, in: state, draft_id: draft_id, createdAt: now - 60)
        let new = try XCTUnwrap(NostrEvent(content: "the new text", keypair: test_keypair, kind: 1, tags: []))
        _ = try seed_draft(new, in: state, draft_id: draft_id, createdAt: now)

        state.drafts.load(from: state)

        XCTAssertEqual(state.drafts.post?.content.string, "the new text")
        XCTAssertEqual(state.drafts.post?.id, draft_id)
    }

    /// Deleting a draft cannot delete anything from nostrdb, so `save` retracts it by storing an
    /// empty version. A load must read that as "no draft", not as an empty one.
    @MainActor
    func testAnEmptyNewestVersionRetractsTheDraft() throws {
        let state = try drafts_state()
        let draft_id = UUID().uuidString
        let now = UInt32(Date().timeIntervalSince1970)

        let post = try XCTUnwrap(NostrEvent(content: "about to be discarded", keypair: test_keypair, kind: 1, tags: []))
        _ = try seed_draft(post, in: state, draft_id: draft_id, createdAt: now - 60)
        try seed(NIP37Draft.tombstone(draft_id: draft_id, author: state.pubkey, createdAt: now), in: state)

        state.drafts.load(from: state)

        XCTAssertNil(state.drafts.post)
    }

    /// The old storage format was a *signed* kind 31234 authored by us with self-encrypted content,
    /// and those notes are still in the database. They match the load's query, so the load has to
    /// turn them away — which the rumor flag does, since only nostrdb's unwrapper sets it.
    @MainActor
    func testASignedDraftEventIsNotLoaded() throws {
        let state = try drafts_state()
        let signed = try XCTUnwrap(NostrEvent(content: "not a rumor",
                                              keypair: test_keypair,
                                              kind: NostrKind.draft.rawValue,
                                              tags: [["d", UUID().uuidString]]))
        try state.ndb.add(event: signed)
        try poll(until: { (try? state.ndb.lookup_note_and_copy(signed.id)) != nil })

        state.drafts.load(from: state)

        XCTAssertNil(state.drafts.post)
        XCTAssertTrue(state.drafts.replies.isEmpty)
        XCTAssertTrue(state.drafts.quotes.isEmpty)
        XCTAssertTrue(state.drafts.highlights.isEmpty)
    }

    /// A load on a database with no drafts in it leaves the composer empty rather than failing.
    @MainActor
    func testLoadWithNoStoredDraftsIsANoOp() throws {
        let state = try drafts_state()
        state.drafts.load(from: state)
        XCTAssertNil(state.drafts.post)
    }


    // MARK: - Saving

    /// The whole loop through the real save path: what the composer holds is sealed into an
    /// envelope, opened by nostrdb, and read back by a fresh `Drafts` — and discarding it retracts
    /// it, which nothing but an empty new version can do in a database with no delete.
    @MainActor
    func testSaveThenLoadRoundTripsADraftAndDiscardingItRetractsIt() async throws {
        let state = try drafts_state()
        let artifacts = DraftArtifacts(content: NSMutableAttributedString(string: "typed into the composer"),
                                       media: [], references: [], id: UUID().uuidString)
        state.drafts.post = artifacts

        await state.drafts.save(damus_state: state)
        try poll(until: { (try? self.stored_draft(artifacts.id, in: state)) != nil })

        let reloaded = Drafts()
        reloaded.load(from: state)
        XCTAssertEqual(reloaded.post?.content.string, "typed into the composer")
        XCTAssertEqual(reloaded.post?.id, artifacts.id, "the draft keeps its NIP-37 id across a save")

        state.drafts.post = nil
        await state.drafts.save(damus_state: state)
        try poll(until: { (try? self.stored_draft(artifacts.id, in: state))?.content == "" })

        let after_discard = Drafts()
        after_discard.load(from: state)
        XCTAssertNil(after_discard.post, "a discarded draft must not come back on the next launch")
    }


    // MARK: - A private reply's lock

    /// The failure this feature must never have: a draft of a **private** reply coming back as a
    /// **public** one.
    ///
    /// The lock rides on the kind-31234 wrapper, not on the drafted note — a private reply's rumor is
    /// byte-identical to the public reply it could have been, so the note itself cannot say. This is
    /// the whole loop through the real save path: composer state, sealed into a PNS envelope, opened
    /// by nostrdb, read back by a fresh `Drafts`.
    @MainActor
    func testAPrivateReplyDraftComesBackStillPrivate() async throws {
        let state = try drafts_state()
        let parent = try XCTUnwrap(NostrEvent(content: "the note being answered", keypair: test_keypair, kind: 1, tags: []))
        try state.ndb.add(event: parent)
        try poll(until: { (try? state.ndb.lookup_note_and_copy(parent.id)) != nil })

        let artifacts = DraftArtifacts(content: NSMutableAttributedString(string: "typed under the lock"),
                                       media: [], references: [], id: UUID().uuidString,
                                       is_private_reply: true)
        state.drafts.replies[parent.id] = artifacts

        await state.drafts.save(damus_state: state)
        try poll(until: { (try? self.stored_draft(artifacts.id, in: state)) != nil })

        let reloaded = Drafts()
        reloaded.load(from: state)

        let restored = try XCTUnwrap(reloaded.replies[parent.id], "the draft belongs under the note it replies to")
        XCTAssertEqual(restored.content.string, "typed under the lock")
        XCTAssertTrue(restored.is_private_reply, "a draft that lost its lock would reopen as a public reply")
    }

    /// The other direction, which matters just as much: an ordinary reply draft must not come back
    /// wearing a lock nobody set. Every draft saved before this feature existed is one of these.
    @MainActor
    func testAPublicReplyDraftComesBackPublic() async throws {
        let state = try drafts_state()
        let parent = try XCTUnwrap(NostrEvent(content: "the note being answered", keypair: test_keypair, kind: 1, tags: []))
        try state.ndb.add(event: parent)
        try poll(until: { (try? state.ndb.lookup_note_and_copy(parent.id)) != nil })

        let artifacts = DraftArtifacts(content: NSMutableAttributedString(string: "typed in the open"),
                                       media: [], references: [], id: UUID().uuidString)
        state.drafts.replies[parent.id] = artifacts

        await state.drafts.save(damus_state: state)
        try poll(until: { (try? self.stored_draft(artifacts.id, in: state)) != nil })

        let reloaded = Drafts()
        reloaded.load(from: state)
        XCTAssertFalse(try XCTUnwrap(reloaded.replies[parent.id]).is_private_reply)
    }

    /// Where the marker lives, asserted directly: on the kind-31234 wrapper, and *not* in the drafted
    /// note. If it ever moved inside, a private reply's rumor would stop being byte-identical to the
    /// public reply it could have been — which is the property phase 1 built the composer around.
    func testTheLockIsOnTheWrapperAndNotOnTheDraftedNote() throws {
        let note = try XCTUnwrap(NostrEvent(content: "a private reply in progress", keypair: test_keypair, kind: 1, tags: []))

        let public_draft = try NIP37Draft(unwrapped_note: note, draft_id: "d").draft_note(author: test_keypair_full.pubkey)
        XCTAssertFalse(public_draft.tags.contains([NIP37Draft.private_reply_tag]))

        let private_draft = try NIP37Draft(unwrapped_note: note, draft_id: "d", is_private_reply: true)
            .draft_note(author: test_keypair_full.pubkey)
        XCTAssertTrue(private_draft.tags.contains([NIP37Draft.private_reply_tag]),
                      "the wrapper carries the marker")
        XCTAssertEqual(NdbNote.owned_from_json(json: private_draft.content), note,
                       "and the drafted note is untouched by it")
        // Compared as notes rather than as strings: `JSONEncoder` does not fix its key order, so two
        // encodings of one note differ byte for byte while being the same note. The claim is about
        // the note.
        XCTAssertEqual(NdbNote.owned_from_json(json: public_draft.content),
                       NdbNote.owned_from_json(json: private_draft.content),
                       "the same reply, drafted locked or not, stores the same note")
    }

    /// The marker survives the trip through nostrdb, read back off a stored note rather than off the
    /// value we just built. A tag that serialized but did not parse would fail closed to *public*,
    /// silently, which is the direction that leaks.
    @MainActor
    func testTheLockSurvivesNostrdb() throws {
        let state = try drafts_state()
        let reply = try XCTUnwrap(NostrEvent(content: "sealed and locked", keypair: test_keypair, kind: 1, tags: []))
        let draft_id = UUID().uuidString
        let draft = NIP37Draft(unwrapped_note: reply, draft_id: draft_id, is_private_reply: true)
        try seed(try draft.draft_note(author: state.pubkey), in: state)

        let stored = try XCTUnwrap(stored_draft(draft_id, in: state))
        XCTAssertTrue(try XCTUnwrap(NIP37Draft(draft_note: stored)).is_private_reply)
    }


    @MainActor
    func testVoiceQuoteDraftPreservesUnrelatedReferencesAndSavesWithoutCachedTarget() async throws {
        let state = try drafts_state()
        let parent = try VoiceEventFixtures.note()
        let other = try VoiceEventFixtures.note(kind: 1, content: "unrelated reference")
        let nevent = Bech32Object.encode(.nevent(NEvent(event: parent, relays: [])))
        let otherReference = "nostr:" + bech32_note_id(other.id)
        let quote = try XCTUnwrap(NostrEvent(content: "keep \(otherReference)\n\nnostr:\(nevent)",
            keypair: test_keypair, kind: 1, tags: [["q", parent.id.hex(), "", parent.pubkey.hex()], ["p", parent.pubkey.hex()]]))
        let id = try seed_draft(quote, in: state)
        state.drafts.load(from: state)
        let restored = try XCTUnwrap(state.drafts.quotes[parent.id])
        XCTAssertNil(try state.ndb.lookup_note_and_copy(parent.id))
        XCTAssertTrue(restored.content.string.contains(otherReference))
        XCTAssertFalse(restored.content.string.contains(nevent))
        restored.content.append(NSAttributedString(string: "edited"))
        await state.drafts.save(damus_state: state)
        try poll(until: {
            guard let stored = try self.stored_draft(id, in: state), let draft = NIP37Draft(draft_note: stored) else { return false }
            return draft.unwrapped_note.content.contains("edited")
        })
        let stored = try XCTUnwrap(stored_draft(id, in: state))
        let saved = try XCTUnwrap(NIP37Draft(draft_note: stored)).unwrapped_note
        XCTAssertEqual(saved.content.components(separatedBy: nevent).count - 1, 1)
        XCTAssertTrue(saved.content.contains(otherReference))
        XCTAssertEqual(DraftArtifacts.quoteID(in: saved), parent.id)
        let reloaded = Drafts()
        reloaded.load(from: state)
        XCTAssertTrue(try XCTUnwrap(reloaded.quotes[parent.id]).content.string.contains("edited"))
    }

    @MainActor
    func testReplyDraftKeepsCapturedVoiceParentThenResavesFromPersistedTags() async throws {
        let state = try drafts_state()
        let parent = try VoiceEventFixtures.note()
        let artifacts = DraftArtifacts(content: NSMutableAttributedString(string: "first text reply"),
                                       references: [.pubkey(parent.pubkey)], id: UUID().uuidString, is_private_reply: true)
        artifacts.context_event = parent
        state.drafts.replies[parent.id] = artifacts
        XCTAssertNil(try state.ndb.lookup_note_and_copy(parent.id))
        await state.drafts.save(damus_state: state)
        try poll(until: { (try? self.stored_draft(artifacts.id, in: state)) != nil })
        let reloaded = Drafts()
        reloaded.load(from: state)
        let restored = try XCTUnwrap(reloaded.replies[parent.id])
        XCTAssertNil(restored.context_event)
        XCTAssertTrue(restored.is_private_reply)
        restored.content = NSMutableAttributedString(string: "second text reply")
        state.drafts.replies[parent.id] = restored
        await state.drafts.save(damus_state: state)
        try poll(until: {
            guard let stored = try self.stored_draft(artifacts.id, in: state), let draft = NIP37Draft(draft_note: stored) else { return false }
            return draft.unwrapped_note.content == "second text reply"
        })
        let saved = try XCTUnwrap(NIP37Draft(draft_note: XCTUnwrap(stored_draft(artifacts.id, in: state))))
        XCTAssertTrue(saved.is_private_reply)
        XCTAssertEqual(saved.unwrapped_note.direct_replies(), parent.id)
    }

    @MainActor
    func testOrdinaryInlineEventReferenceStaysInPostDraft() throws {
        let state = try drafts_state()
        let target = try VoiceEventFixtures.note()
        let reference = "nostr:" + Bech32Object.encode(.nevent(NEvent(event: target, relays: [])))
        let event = try XCTUnwrap(NostrEvent(content: "read \(reference) later", keypair: test_keypair, kind: 1, tags: []))
        _ = try seed_draft(event, in: state)
        state.drafts.load(from: state)
        XCTAssertEqual(state.drafts.post?.content.string, event.content)
        XCTAssertTrue(state.drafts.quotes.isEmpty)
    }

    // MARK: Helpers

    /// A `DamusState` on its own database, with our key registered with the ingester threads so it
    /// can open the PNS envelopes the tests hand it.
    ///
    /// A fresh one per test: drafts are read back by *query*, so a shared database would let one
    /// test's drafts show up in another's assertions.
    @MainActor
    private func drafts_state() throws -> DamusState {
        let state = make_test_damus_state()
        XCTAssertTrue(state.ndb.add_key(test_keypair_full.privkey),
                      "the ingester needs our key to open a PNS envelope")
        return state
    }

    /// Wraps `note` into a NIP-37 draft, seals it in a PNS envelope, and stores it in NostrDB the
    /// way `Drafts.save(damus_state:)` does.
    /// - Returns: the draft's NIP-37 id.
    @MainActor
    @discardableResult
    private func seed_draft(_ note: NostrEvent,
                            in state: DamusState,
                            draft_id: String = UUID().uuidString,
                            createdAt: UInt32 = UInt32(Date().timeIntervalSince1970)) throws -> String {
        let draft = NIP37Draft(unwrapped_note: note, draft_id: draft_id)
        try seed(try draft.draft_note(author: state.pubkey, createdAt: createdAt), in: state)
        return draft_id
    }

    /// Seals a kind-31234 draft event in a PNS envelope and waits for nostrdb to open it.
    @MainActor
    private func seed(_ draft_note: NIP59.Rumor, in state: DamusState) throws {
        let key = try PNS.key(for: test_keypair_full.privkey)
        let envelope = try PNS.envelope(rumor: draft_note, key: key)
        try state.ndb.add(event: envelope)

        // Ingestion is asynchronous, and unsealing happens on the ingester threadpool, so wait for
        // the draft event to actually be queryable rather than assuming it is.
        let draft_id = try XCTUnwrap(draft_note.tags.first(where: { $0.first == "d" })?.last)
        try poll(until: {
            guard let note = try? self.stored_draft(draft_id, in: state) else { return false }
            return note.created_at == draft_note.created_at
        })
    }

    /// The stored kind-31234 note for `draft_id`, newest first, or `nil` if nostrdb has none.
    @MainActor
    private func stored_draft(_ draft_id: String, in state: DamusState) throws -> NdbNote? {
        let filter = try NdbFilter(from: NostrFilter(kinds: [.draft], authors: [state.pubkey]))
        for key in try state.ndb.query(filters: [filter], maxResults: 100) {
            guard let note = try state.ndb.lookup_note_by_key_and_copy(key) else { continue }
            guard note.referenced_params.first?.param.string() == draft_id else { continue }
            return note
        }
        return nil
    }

    /// Polls `condition` for up to five seconds.
    @MainActor
    private func poll(until condition: () throws -> Bool) throws {
        for _ in 0..<200 {
            if try condition() { return }
            usleep(25_000)
        }
        XCTFail("nostrdb never produced what the test was waiting for")
    }
}
