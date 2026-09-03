//
//  DraftTests.swift
//  damusTests
//
//  Created by Daniel D’Aquino on 2025-01-15

import XCTest
@testable import damus

class DraftTests: XCTestCase {
    func testRoundtripNIP37Draft() {
        let test_note =
                NostrEvent(
                    content: "Test",
                    keypair: test_keypair_full.to_keypair(),
                    createdAt: UInt32(Date().timeIntervalSince1970 - 100)
                )!
        let draft = try! NIP37Draft(unwrapped_note: test_note, draft_id: "test", keypair: test_keypair_full)!
        XCTAssertEqual(draft.unwrapped_note, test_note)
    }


    // MARK: - Loading saved drafts

    /// `Drafts.load(from:)` reads and decrypts saved drafts off the main thread, so
    /// `finish_loading(with:)` has to wait for that read. If it did not, the post composer could
    /// open on an empty draft and the user would start a fresh post over a saved one.
    @MainActor
    func testFinishLoadingWaitsForTheBackgroundRead() throws {
        let state = try reset_drafts()
        defer { state.settings.draft_event_ids = [] }

        let post = try XCTUnwrap(NostrEvent(content: "a saved post draft", keypair: test_keypair, kind: 1, tags: []))
        try seed_draft(post, in: state)

        state.drafts.load(from: state)
        state.drafts.finish_loading(with: state)

        XCTAssertEqual(state.drafts.post?.content.string, "a saved post draft")
    }

    /// A saved draft that replies to a note belongs under `replies`, not `post`.
    @MainActor
    func testLoadFilesReplyDraftsUnderTheNoteTheyReplyTo() throws {
        let state = try reset_drafts()
        defer { state.settings.draft_event_ids = [] }

        let replied_to = try XCTUnwrap(NoteId(hex: "7c7d37bc8c04d2ec65cbc7d9275253e6b5cc34b5d10439f158194a3feefa8d52"))
        let reply = try XCTUnwrap(NostrEvent(content: "a saved reply draft", keypair: test_keypair, kind: 1, tags: [["e", replied_to.hex()]]))
        try seed_draft(reply, in: state)

        state.drafts.load(from: state)
        state.drafts.finish_loading(with: state)

        XCTAssertNil(state.drafts.post)
        XCTAssertEqual(state.drafts.replies[replied_to]?.content.string, "a saved reply draft")
    }

    /// A saved highlight draft belongs under `highlights`, keyed on the text it highlights. Its
    /// editable content is the comment on the highlight, not the highlighted text itself.
    @MainActor
    func testLoadFilesHighlightDraftsUnderTheirHighlight() throws {
        let state = try reset_drafts()
        defer { state.settings.draft_event_ids = [] }

        let source_url = try XCTUnwrap(URL(string: "https://damus.io/"))
        let highlight = try XCTUnwrap(NostrEvent(content: "the highlighted text",
                                                 keypair: test_keypair,
                                                 kind: NostrKind.highlight.rawValue,
                                                 tags: [["r", source_url.absoluteString, "source"],
                                                        ["comment", "a saved highlight draft"]]))
        try seed_draft(highlight, in: state)

        state.drafts.load(from: state)
        state.drafts.finish_loading(with: state)

        XCTAssertNil(state.drafts.post)
        let expected = HighlightContentDraft(selected_text: "the highlighted text", source: .external_url(source_url))
        XCTAssertEqual(state.drafts.highlights[expected]?.content.string, "a saved highlight draft")
    }

    /// The post composer calls `finish_loading(with:)` every time it appears, including before
    /// anything has ever been loaded, so it has to be a no-op rather than a hang.
    @MainActor
    func testFinishLoadingWithoutALoadIsANoOp() {
        let drafts = Drafts()
        drafts.finish_loading(with: test_damus_state)
        XCTAssertNil(drafts.post)
    }


    // MARK: Helpers

    /// Hands back the shared test state with its drafts emptied, since the tests above share it.
    @MainActor
    private func reset_drafts() throws -> DamusState {
        let state = test_damus_state
        state.drafts.finish_loading(with: state)  // Drop anything a previous test left in flight
        state.drafts.post = nil
        state.drafts.replies = [:]
        state.drafts.quotes = [:]
        state.drafts.highlights = [:]
        state.settings.draft_event_ids = []
        return state
    }

    /// Wraps `note` into a NIP-37 draft, stores it in NostrDB, and points the settings at it.
    @MainActor
    private func seed_draft(_ note: NostrEvent, in state: DamusState) throws {
        let draft = try XCTUnwrap(try NIP37Draft(unwrapped_note: note, draft_id: UUID().uuidString, keypair: test_keypair_full))
        try state.ndb.add(event: draft.wrapped_note)

        // `add(event:)` hands the note to nostrdb's writer, which is not synchronous with the
        // read side, so wait for it to land rather than assuming it has.
        for _ in 0..<200 {
            if (try? state.ndb.lookup_note_and_copy(draft.wrapped_note.id)) != nil { break }
            usleep(25_000)
        }

        state.settings.draft_event_ids = (state.settings.draft_event_ids ?? []) + [draft.wrapped_note.id.hex()]
    }
}
