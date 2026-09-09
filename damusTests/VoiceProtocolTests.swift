import XCTest
@testable import damus

enum VoiceEventFixtures {
    static func note(kind: UInt32 = 1808, content: String = "A searchable voice transcript.", tags: [[String]] = [],
                     keys: FullKeypair = generate_new_keypair(), time: UInt32 = 1_780_000_000) throws -> NostrEvent {
        let media = try VoiceMediaReference(url: "https://blossom.band/opaque?download=exact",
                                           sha256: String(repeating: "a", count: 64), mimeType: "audio/mp4", duration: 1.25)
        return try XCTUnwrap(NostrEvent(content: content, keypair: keys.to_keypair(), kind: kind,
                                       tags: (kind == 1808 ? media.tags : []) + tags, createdAt: time))
    }

    static func draft(keys: FullKeypair, kind: VoiceContext.Kind = .post, target: NostrEvent? = nil, recipient: String? = nil) throws -> VoiceDraft {
        let context = VoiceContext(account: keys.pubkey.hex(), kind: kind, targetID: target?.id.hex(),
                                   targetJSON: target.flatMap { event_to_json(ev: $0) }, recipient: recipient)
        var draft = VoiceDraft(context: context, locale: "en-US")
        draft.takeID = UUID()
        draft.transcript = "A local transcript for review."
        draft.duration = 1.25
        draft.sha256 = String(repeating: "a", count: 64)
        draft.size = 1234
        let reference = try VoiceMediaReference(url: "https://blossom.band/opaque?download=exact",
                                               sha256: draft.sha256!, mimeType: "audio/mp4", duration: try XCTUnwrap(draft.duration))
        draft.receipt = VoiceUploadReceipt(server: "https://blossom.band", reference: reference, size: draft.size!)
        return draft
    }

    static func mutatedJSON(_ event: NostrEvent, key: String, value: Any) throws -> NostrEvent {
        let json = try XCTUnwrap(event_to_json(ev: event))
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        object[key] = value
        let encoded = try JSONSerialization.data(withJSONObject: object)
        return try XCTUnwrap(NdbNote.owned_from_json(json: String(decoding: encoded, as: UTF8.self)))
    }
}

final class VoiceProtocolTests: XCTestCase {
    func testSignedPostAndExactRetry() throws {
        let keys = generate_new_keypair()
        var draft = try VoiceEventFixtures.draft(keys: keys)
        let event = try VoiceEventBuilder.build(draft, keypair: keys, clientTag: ["client", "Damus"])
        XCTAssertTrue(event.verify())
        XCTAssertEqual(event.known_kind, .voice)
        XCTAssertEqual(event.content, draft.transcript)
        XCTAssertFalse(event.is_reply())
        draft.eventJSON = event_to_json(ev: event)
        for _ in 0..<16 { XCTAssertEqual(try VoiceEventBuilder.restoredEvent(draft).id, event.id) }
        let encoded = try JSONEncoder().encode(draft)
        let restored = try JSONDecoder().decode(VoiceDraft.self, from: encoded)
        XCTAssertEqual(try VoiceEventBuilder.restoredEvent(restored).id, event.id)
        XCTAssertEqual(restored.receipt?.reference.url, "https://blossom.band/opaque?download=exact")
    }

    func testMarkersOverrideEarlierLegacyReferences() throws {
        let legacy = try VoiceEventFixtures.note(kind: 1), root = try VoiceEventFixtures.note(), parent = try VoiceEventFixtures.note(kind: 1)
        for kind: UInt32 in [1, 1808] {
            let note = try VoiceEventFixtures.note(kind: kind, tags: [["e", legacy.id.hex()],
                ["e", root.id.hex(), "", "root"], ["e", parent.id.hex(), "", "reply"]])
            XCTAssertEqual(note.thread_id(), root.id)
            XCTAssertEqual(note.direct_reply_ref()?.note_id, parent.id)
            XCTAssertEqual(VoiceEventBuilder.replyTags(parent: note).first?[1], root.id.hex())
        }
    }

    func testMixedRepliesPreserveImmediateParentAndKnownRoot() throws {
        let keys = generate_new_keypair()
        for rootKind: UInt32 in [1, 1808] {
            let root = try VoiceEventFixtures.note(kind: rootKind)
            let first = try VoiceEventBuilder.build(VoiceEventFixtures.draft(keys: keys, kind: .reply, target: root), keypair: keys)
            XCTAssertEqual(first.tags.strings().filter { $0.first == "e" }.map { $0[1] }, [root.id.hex(), root.id.hex()])
            for parentKind: UInt32 in [1, 1808] {
                let parent = try VoiceEventFixtures.note(kind: parentKind, tags: VoiceEventBuilder.replyTags(parent: root))
                let reply = try VoiceEventBuilder.build(VoiceEventFixtures.draft(keys: keys, kind: .reply, target: parent), keypair: keys)
                XCTAssertEqual(reply.tags.strings().filter { $0.first == "e" }.map { $0[1] }, [root.id.hex(), parent.id.hex()])
                XCTAssertTrue(reply.tags.strings().contains(["p", parent.pubkey.hex()]))
                XCTAssertEqual(reply.thread_id(), root.id)
                XCTAssertEqual(reply.direct_reply_ref()?.note_id, parent.id)
            }
        }
    }

    func testLegacyRootAndReplyOnlyParent() throws {
        let root = try VoiceEventFixtures.note(kind: 1)
        let legacy = try VoiceEventFixtures.note(tags: [["e", root.id.hex()]])
        let tags = VoiceEventBuilder.replyTags(parent: legacy)
        XCTAssertEqual(tags.filter { $0.first == "e" }.map { $0[1] }, [root.id.hex(), legacy.id.hex()])
        let replyOnly = try VoiceEventFixtures.note(tags: [["e", root.id.hex(), "", "reply"]])
        let replyTags = VoiceEventBuilder.replyTags(parent: replyOnly)
        XCTAssertEqual(replyTags.filter { $0.first == "e" }.count, 1)
        XCTAssertEqual(replyTags.first?[3], "reply")
        let sourceOnly = try VoiceEventFixtures.note(tags: [["e", root.id.hex(), "", "", "repost-source"]])
        XCTAssertNil(sourceOnly.thread_reply())
        let sourceTags = VoiceEventBuilder.replyTags(parent: sourceOnly)
        XCTAssertEqual(sourceTags.filter { $0.first == "e" }.map { $0[1] }, [sourceOnly.id.hex(), sourceOnly.id.hex()])
    }

    func testVoiceQuotesTextAndVoiceWithoutReplyRelationship() throws {
        let keys = generate_new_keypair()
        for kind: UInt32 in [1, 1808] {
            let target = try VoiceEventFixtures.note(kind: kind)
            let draft = try VoiceEventFixtures.draft(keys: keys, kind: .quote, target: target)
            let quote = try VoiceEventBuilder.build(draft, keypair: keys)
            XCTAssertTrue(quote.tags.strings().contains(["q", target.id.hex(), "", target.pubkey.hex()]))
            XCTAssertTrue(quote.tags.strings().contains(["p", target.pubkey.hex()]))
            XCTAssertFalse(quote.tags.strings().contains { $0.first == "e" })
            XCTAssertTrue(quote.content.contains("nostr:nevent"))
            XCTAssertEqual(quote.referenced_quote_ids.first?.note_id, target.id)
        }
    }

    func testVoiceRepostValidatesOriginalAndIgnoresMarkedSourceAttribution() throws {
        let original = try VoiceEventFixtures.note()
        let keys = generate_new_keypair()
        let repost = try XCTUnwrap(make_boost_event(keypair: keys, boosted: original, relayURL: nil))
        XCTAssertEqual(repost.known_kind, .voice_repost)
        XCTAssertTrue(repost.verify_voice_repost())
        XCTAssertEqual(repost.get_inner_event()?.id, original.id)
        XCTAssertEqual(repost.get_inner_event()?.pubkey, original.pubkey)
        XCTAssertNotEqual(repost.pubkey, original.pubkey)
        let source = try VoiceEventFixtures.note()
        let tags = [["e", source.id.hex(), "", "", "repost-source"],
                    ["p", source.pubkey.hex(), "", "repost-source"]] + repost.tags.strings()
        let withSource = try VoiceEventFixtures.note(kind: 1809, content: repost.content, tags: tags, keys: keys)
        XCTAssertTrue(withSource.verify_voice_repost())
        XCTAssertEqual(withSource.get_inner_event()?.id, original.id)
    }

    func testForgedAndConflictingRepostsCannotExposeAnOriginal() throws {
        let original = try VoiceEventFixtures.note()
        let keys = generate_new_keypair()
        let json = try XCTUnwrap(event_to_json(ev: original))
        let validTags = [["e", original.id.hex()], ["p", original.pubkey.hex()], ["k", "1808"]]
        let other = try VoiceEventFixtures.note()
        let invalidTags = [
            Array(validTags.dropLast()), validTags + [["k", "1"]],
            validTags + [["e", other.id.hex()]], validTags + [["p", other.pubkey.hex()]],
            [["e", "not-an-id"], validTags[1], validTags[2]],
            [validTags[0], ["p"], validTags[2]],
            [["e", other.id.hex()], validTags[1], validTags[2]]
        ]
        for tags in invalidTags {
            let wrapper = try VoiceEventFixtures.note(kind: 1809, content: json, tags: tags, keys: keys)
            XCTAssertFalse(wrapper.verify_voice_repost())
            XCTAssertNil(wrapper.get_inner_event())
        }
        let valid = try VoiceEventFixtures.note(kind: 1809, content: json, tags: validTags, keys: keys)
        let forgedOuter = try VoiceEventFixtures.mutatedJSON(valid, key: "sig", value: String(repeating: "0", count: 128))
        XCTAssertFalse(forgedOuter.verify_voice_repost())
        XCTAssertNil(forgedOuter.get_inner_event())
        let forgedInner = try VoiceEventFixtures.mutatedJSON(original, key: "content", value: "Forged transcript")
        let wrapper = try VoiceEventFixtures.note(kind: 1809, content: XCTUnwrap(event_to_json(ev: forgedInner)), tags: validTags, keys: keys)
        XCTAssertFalse(wrapper.verify_voice_repost())
        XCTAssertNil(wrapper.get_inner_event())
        XCTAssertNil(make_boost_event(keypair: keys, boosted: forgedInner, relayURL: nil))
    }

    func testRestoredDraftRejectsChangedTranscriptDurationReceiptOrContext() throws {
        let keys = generate_new_keypair()
        var saved = try VoiceEventFixtures.draft(keys: keys)
        saved.eventJSON = event_to_json(ev: try VoiceEventBuilder.build(saved, keypair: keys))
        var changed = saved; changed.transcript = "Different transcript"
        XCTAssertThrowsError(try VoiceEventBuilder.restoredEvent(changed))
        changed = saved; changed.duration = 123
        XCTAssertThrowsError(try VoiceEventBuilder.restoredEvent(changed))
        changed = saved; changed.sha256 = String(repeating: "b", count: 64)
        XCTAssertThrowsError(try VoiceEventBuilder.restoredEvent(changed))
        changed = saved; changed.takeID = nil
        XCTAssertThrowsError(try VoiceEventBuilder.restoredEvent(changed))
        changed = saved; changed.pendingTakeID = UUID()
        XCTAssertThrowsError(try VoiceEventBuilder.restoredEvent(changed))
        let other = generate_new_keypair()
        XCTAssertThrowsError(try VoiceEventBuilder.build(saved, keypair: other))
    }

    func testProfileRecipientSurvivesRestartAndIsNotAReply() throws {
        let keys = generate_new_keypair(), recipient = generate_new_keypair().pubkey.hex()
        let draft = try VoiceEventFixtures.draft(keys: keys, recipient: recipient)
        let restored = try JSONDecoder().decode(VoiceDraft.self, from: JSONEncoder().encode(draft))
        let event = try VoiceEventBuilder.build(restored, keypair: keys)
        XCTAssertTrue(event.tags.strings().contains(["p", recipient]))
        XCTAssertFalse(event.tags.strings().contains { $0.first == "e" })
        XCTAssertNotEqual(restored.context.key, "post")
    }
}
