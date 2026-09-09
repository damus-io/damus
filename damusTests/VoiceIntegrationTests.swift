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
        let video = try XCTUnwrap(URL(string: "https://media.example/separate-video.mp4"))
        let primaryAlias = try XCTUnwrap(URL(string: "https://MEDIA.example:443/audio.mp4?exact=1#play"))
        let transcript = "Signed transcript remains readable."
        let voice = try XCTUnwrap(NostrEvent(content: transcript, keypair: test_keypair, kind: 1808,
            tags: [["url", primary.absoluteString], ["imeta", "url " + primary.absoluteString, "m audio/mp4"],
                   ["imeta", "url " + cover.absoluteString, "m image/jpeg"]]))
        let content = NoteArtifactsSeparated.just_content(transcript).content
        let unsafe = NoteArtifactsSeparated(content: content, words: 4,
            urls: [.media(.video(primary)), .media(.image(primary)), .link(primary), .media(.image(cover)),
                   .link(other), .media(.video(video)), .media(.video(primaryAlias))], invoices: [])
        let safe = unsafe.voiceSafe(for: voice)
        XCTAssertEqual(safe.urls.map(\.url), [cover, other, video])
        XCTAssertEqual(safe.media.compactMap { if case .video(let url) = $0 { return url }; return nil }, [video])
        XCTAssertEqual(safe.content, content)
        XCTAssertEqual(event_image_metadata(ev: voice).map(\.url), [cover])
        XCTAssertThrowsError(try VoiceMediaReference(tags: voice.tags.strings()))
        let text = try VoiceEventFixtures.note(kind: 1)
        XCTAssertEqual(unsafe.voiceSafe(for: text).urls.count, unsafe.urls.count)
    }

    /// Feed/profile/quote/repost rows share this content-rendering and image-metadata path.
    @MainActor
    func testVoiceAttachmentsRenderFromWireTagsContentAndVerifiedReposts() async throws {
        let state = make_test_damus_state()
        let recording = "https://media.example/recording.mp4?exact=1"
        let photo = "https://media.example/map.jpg"
        let secondPhoto = "https://media.example/photo?token=Two%2FThree"
        let inlineVideo = "https://media.example/walk.mp4"
        let taggedVideo = "https://media.example/video?token=AbC%2F123"
        let article = "https://example.com/route"
        let extraAudio = "https://media.example/extra.m4a"
        let hash = String(repeating: "a", count: 64)
        let tags = [
            ["url", recording], ["blossom", hash, "audio/mp4"], ["duration", "7.4"],
            ["imeta", "url " + recording, "m audio/mp4", "x " + hash],
            ["imeta", "url " + photo, "m image/jpeg", "alt Map of the riverside walking route", "dim 1200x800"],
            ["imeta", "url " + secondPhoto, "m image/jpeg", "alt The footbridge where the walk starts",
             "dim 800x600", "blurhash LEHV6nWB2yk8pyo0adR*.7kCMdnj"],
            ["imeta", "url " + taggedVideo, "m video/mp4"],
            ["r", article, "Riverside walking route"],
            // An extra listening link does not declare another primary recording.
            ["r", extraAudio, "Related recording"]
        ]
        let content = ["Let's use this route.", photo, inlineVideo, recording].joined(separator: "\n")
        let signed = try XCTUnwrap(NostrEvent(content: content, keypair: test_keypair, kind: 1808, tags: tags))
        let wire = try XCTUnwrap(NdbNote.owned_from_json(json: XCTUnwrap(event_to_json(ev: signed))))
        XCTAssertTrue(wire.verify())
        let rendered = render_immediately_available_note_content(ndb: state.ndb, ev: wire, profiles: state.profiles, keypair: state.keypair)
        guard case .separated(let artifacts) = rendered else { return XCTFail("Voice content needs media artifacts") }
        XCTAssertEqual(artifacts.images.map(\.absoluteString), [photo, secondPhoto])
        XCTAssertEqual(artifacts.media.map { $0.url.absoluteString }, [photo, inlineVideo, secondPhoto, taggedVideo])
        XCTAssertEqual(artifacts.links.map(\.absoluteString), [article, extraAudio])
        XCTAssertTrue(String(artifacts.content.attributed.characters).contains("Let's use this route."))
        XCTAssertEqual(try VoiceMediaReference(tags: wire.tags.strings()).url, recording)

        let metadata = event_image_metadata(ev: wire)
        XCTAssertEqual(metadata.map { $0.url.absoluteString }, [photo, secondPhoto])
        XCTAssertEqual(metadata.first?.dim, ImageMetaDim(width: 1200, height: 800))
        XCTAssertEqual(metadata.last?.dim, ImageMetaDim(width: 800, height: 600))
        process_image_metadatas(cache: state.events, ev: wire)
        XCTAssertNotNil(state.events.lookup_img_metadata(url: URL(string: secondPhoto)!),
                        "An image without blurhash must not skip later image metadata")

        // Previously cached artifacts dropped videos. The retained attributed links recover them.
        let oldCache = NoteArtifactsSeparated(content: artifacts.content, words: artifacts.words,
            urls: artifacts.urls.filter { $0.is_video == nil }, invoices: artifacts.invoices)
        let recovered = oldCache.voiceSafe(for: wire)
        XCTAssertEqual(recovered.urls.map(\.url), artifacts.urls.map(\.url))
        XCTAssertEqual(recovered.voiceSafe(for: wire).urls.map(\.url), recovered.urls.map(\.url))

        let previousUndistract = state.settings.undistractMode
        defer { state.settings.undistractMode = previousUndistract }
        state.settings.undistractMode = false
        state.events.get_cache_data(wire.id).artifacts_model.state = .loaded(.separated(oldCache))
        let view = NoteContentView(damus_state: state, event: wire, blur_images: false, size: .normal, options: [])
        guard case .separated(let displayed) = view.note_artifacts else { return XCTFail("Row lost voice artifacts") }
        XCTAssertEqual(displayed.urls.map(\.url), artifacts.urls.map(\.url))
        state.settings.undistractMode = true
        guard case .separated(let hidden) = view.note_artifacts else { return XCTFail("Undistract content should be text") }
        XCTAssertTrue(hidden.urls.isEmpty, "Tag attachments must respect undistract mode")
        state.settings.undistractMode = false

        let repost = try XCTUnwrap(make_boost_event(keypair: generate_new_keypair(), boosted: wire, relayURL: nil))
        let verifiedOriginal = await Task.detached { repost.get_inner_event() }.value
        let original = try XCTUnwrap(verifiedOriginal)
        let repostContent = render_immediately_available_note_content(ndb: state.ndb, ev: original, profiles: state.profiles, keypair: state.keypair)
        guard case .separated(let repostArtifacts) = repostContent else { return XCTFail("Repost lost voice attachments") }
        XCTAssertEqual(repostArtifacts.urls.map(\.url), artifacts.urls.map(\.url))
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
