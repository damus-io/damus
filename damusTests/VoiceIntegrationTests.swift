import XCTest
@testable import damus

final class VoiceIntegrationTests: XCTestCase {
    func testNegativeRelayOKKeepsPendingEventUntilRealAcceptance() async throws {
        let keys = generate_new_keypair()
        var draft = try VoiceEventFixtures.draft(keys: keys)
        let event = try VoiceEventBuilder.build(draft, keypair: keys)
        draft.eventJSON = event_to_json(ev: event)
        let sent = draft
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VoiceDraftStore(root: root)
        let lease = try await store.acquire(context: draft.context)
        try await store.save(draft, lease: lease)
        let pool = RelayPool(ndb: nil)
        let box = PostBox(pool: pool)
        let relay = try XCTUnwrap(RelayURL("wss://voice-relay.invalid"))
        let unrelated = try XCTUnwrap(RelayURL("wss://unrelated.invalid"))
        // A queued destination without a connection permits deterministic ACKs and no network send.
        await box.send(event, to: [relay], delay: 3600)
        await box.sendVoice(event, isActive: { true }) { update in
            do { try await store.recordDelivery(update, for: sent) }
            catch { XCTFail("Failed to update delivery: \(error)") }
        }
        await box.handle_event(relay_id: unrelated, .nostr_event(.ok(CommandResult(event_id: event.id, ok: true, msg: "unrelated"))))
        let unknownACK = try await store.load(context: sent.context)
        XCTAssertTrue(try XCTUnwrap(unknownACK).acceptedRelays.isEmpty)
        await box.handle_event(relay_id: relay, .nostr_event(.ok(CommandResult(event_id: event.id, ok: false, msg: "blocked: test rejection"))))
        let rejected = try await store.load(context: sent.context)
        XCTAssertEqual(rejected?.phase, .rejected)
        XCTAssertEqual(rejected?.eventJSON, sent.eventJSON)
        XCTAssertEqual(rejected?.receipt, sent.receipt)
        let pending = await box.events[event.id]
        XCTAssertEqual(pending?.remaining.map(\.relay), [relay])
        await box.handle_event(relay_id: relay, .nostr_event(.ok(CommandResult(event_id: event.id, ok: true, msg: ""))))
        let accepted = try await store.load(context: sent.context)
        XCTAssertEqual(accepted?.phase, .accepted)
        XCTAssertEqual(accepted?.acceptedRelays, [relay.absoluteString])
        let finished = await box.events[event.id]
        XCTAssertNil(finished)
        XCTAssertEqual(accepted?.eventJSON, sent.eventJSON)
    }

    func testClosingCompositionKeepsSubmittedDeliveryUntilAccountCloses() async throws {
        let keys = generate_new_keypair()
        var draft = try VoiceEventFixtures.draft(keys: keys)
        let event = try VoiceEventBuilder.build(draft, keypair: keys)
        draft.eventJSON = event_to_json(ev: event)
        let sent = draft
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = VoiceDraftStore(root: root)
        let lease = try await store.acquire(context: draft.context)
        try await store.save(draft, lease: lease)
        let lifetime = VoiceAccountLifetime()
        let box = PostBox(pool: RelayPool(ndb: nil))
        await box.sendVoice(event, isActive: { lifetime.isActive }) { update in
            do { try await store.recordDelivery(update, for: sent) }
            catch { XCTFail("Failed to update delivery: \(error)") }
        }
        let queued = try await store.load(context: sent.context)
        XCTAssertEqual(queued?.phase, .retryable)
        XCTAssertTrue(try XCTUnwrap(queued).acceptedRelays.isEmpty)
        try await store.discard(sent, lease: lease)
        await store.release(context: sent.context, owner: lease.id)
        let stillQueued = await box.events[event.id]
        XCTAssertEqual(stillQueued?.event.id, event.id)
        lifetime.invalidate()
        await box.try_flushing_events()
        let pending = await box.events[event.id]
        XCTAssertNil(pending)
        let restored = await VoiceDraftStore(root: root).load(context: sent.context)
        XCTAssertNil(restored)
        let closed = await store.load(context: sent.context)
        XCTAssertNil(closed)
    }

    func testPrimaryAudioCannotUseGenericVideoImageOrPreviewPaths() throws {
        let primary = try XCTUnwrap(URL(string: "https://media.example/audio.mp4?exact=1"))
        let cover = try XCTUnwrap(URL(string: "https://media.example/cover.jpg"))
        let other = try XCTUnwrap(URL(string: "https://media.example/article"))
        let transcript = "Signed transcript remains readable."
        let voice = try XCTUnwrap(NostrEvent(content: transcript, keypair: test_keypair, kind: 1808,
            tags: [["url", primary.absoluteString], ["imeta", "url " + primary.absoluteString, "m audio/mp4"],
                   ["imeta", "url " + cover.absoluteString, "m image/jpeg"]]))
        let content = NoteArtifactsSeparated.just_content(transcript).content
        let unsafe = NoteArtifactsSeparated(content: content, words: 4,
            urls: [.media(.video(primary)), .media(.image(primary)), .link(primary), .media(.image(cover)), .link(other)], invoices: [])
        let safe = unsafe.voiceSafe(for: voice)
        XCTAssertEqual(safe.urls.map(\.url), [cover, other])
        XCTAssertEqual(safe.content, content)
        XCTAssertEqual(event_image_metadata(ev: voice).map(\.url), [cover])
        XCTAssertThrowsError(try VoiceMediaReference(tags: voice.tags.strings()))
        let text = try VoiceEventFixtures.note(kind: 1)
        XCTAssertEqual(unsafe.voiceSafe(for: text).urls.count, unsafe.urls.count)
    }

    @MainActor
    func testNotificationsUseVerifiedOriginalAndRetainVoiceDeepLinkType() async throws {
        let state = make_test_damus_state()
        state.settings.repost_notification = true
        let original = try VoiceEventFixtures.note(keys: test_keypair_full)
        let repost = try XCTUnwrap(make_boost_event(keypair: generate_new_keypair(), boosted: original, relayURL: nil))
        let fresh = try XCTUnwrap(NdbNote.owned_from_json(json: XCTUnwrap(event_to_json(ev: repost))))
        XCTAssertNil(generate_local_notification_object(ndb: state.ndb, from: fresh, state: state))
        let verified = await Task.detached { fresh.get_inner_event() != nil }.value
        XCTAssertTrue(verified)
        let notification = try XCTUnwrap(generate_local_notification_object(ndb: state.ndb, from: fresh, state: state))
        XCTAssertEqual(notification.target.id, original.id)
        XCTAssertEqual(notification.event.pubkey, repost.pubkey)
        XCTAssertEqual(notification.type, .repost)
        XCTAssertEqual(LocalNotificationType.from(note: original), .mention)
        XCTAssertEqual(LocalNotificationType.from(note: fresh), .repost)
        let forged = try VoiceEventFixtures.mutatedJSON(fresh, key: "sig", value: String(repeating: "0", count: 128))
        let invalid = await Task.detached { forged.get_inner_event() != nil }.value
        XCTAssertFalse(invalid)
        XCTAssertNil(generate_local_notification_object(ndb: state.ndb, from: forged, state: state))
    }
}
