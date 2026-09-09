import AVFoundation
import XCTest
import UIKit
@testable import damus

@MainActor
final class VoiceComposerModelTests: XCTestCase {
    private func fixture(recorder: ControlledVoiceRecorder = ControlledVoiceRecorder(),
                         transcriber: ControlledVoiceTranscriber = ControlledVoiceTranscriber(),
                         uploader: ControlledVoiceUploader = ControlledVoiceUploader(),
                         action: PostAction = .posting(.none)) async throws -> VoiceComposerFixture {
        let state = generate_test_damus_state(mock_profile_info: nil, addNdbToRelayPool: false)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let store = VoiceDraftStore(root: root)
        let publisher = ControlledVoicePublisher(store: store)
        let model = VoiceComposerModel(state: state, action: action, store: store, recorder: recorder,
                                       transcriber: transcriber, uploader: uploader, photoUploader: ControlledVoicePhotoUploader(), publisher: publisher)
        let fixture = VoiceComposerFixture(model: model, state: state, store: store, root: root,
                                            recorder: recorder, transcriber: transcriber, uploader: uploader, publisher: publisher)
        addTeardownBlock { @MainActor in
            model.disappear()
            state.voiceLifetime.invalidate()
            await recorder.startGate?.open()
            await recorder.finishGate?.open()
            await transcriber.gate?.open()
            await uploader.gate?.open()
            await model.waitUntilClosed()
            VoicePlayback.shared.stop()
            try? FileManager.default.removeItem(at: root)
        }
        XCTAssertEqual(model.mode, .text)
        model.changeMode(.audio)
        try await eventually { model.draft != nil && !model.busy }
        return fixture
    }

    private func eventually(_ condition: @escaping @MainActor () async throws -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !(try await condition()) {
            guard Date() < deadline else { XCTFail("Composer transition did not finish"); throw VoiceFailure("Test transition timed out") }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func record(_ f: VoiceComposerFixture) async throws {
        f.model.beginHold()
        try await eventually { f.model.phase == .recording }
        f.model.releaseHold()
        try await eventually { !f.model.busy }
    }

    /// Local review supports the feed's seeking and playback ownership without publishing.
    func testPreviewSeeksPausesAndStopsWhenSwitchingToText() async throws {
        let f = try await fixture()
        try await record(f)
        let draft = try XCTUnwrap(f.model.draft)
        let take = try XCTUnwrap(draft.takeID)
        let playback = VoicePlayback.shared
        let speed = playback.playbackRate
        defer { while playback.playbackRate != speed { playback.cyclePlaybackRate() } }
        f.model.seekPreview(0.25)
        f.model.preview()
        XCTAssertTrue(f.model.previewLoading)
        XCTAssertTrue(f.model.canSend)
        try await eventually { !f.model.previewLoading }
        XCTAssertNil(f.model.error)
        XCTAssertEqual(playback.owner, take.uuidString)
        XCTAssertTrue(playback.isPlaying)
        XCTAssertGreaterThanOrEqual(playback.position, 0.25)
        f.model.preview()
        XCTAssertFalse(playback.isPlaying)
        f.model.seekPreview(0.1)
        XCTAssertEqual(playback.position, 0.1, accuracy: 0.03)
        playback.cyclePlaybackRate()
        XCTAssertFalse(playback.isPlaying)
        f.model.preview()
        XCTAssertTrue(playback.isPlaying)
        f.model.changeMode(.text)
        XCTAssertNil(playback.owner)
        XCTAssertNil(playback.requestedOwner)
        XCTAssertEqual(f.model.draft, draft)
        let uploads = await f.uploader.calls, posts = await f.publisher.events.count
        XCTAssertEqual(uploads, 0)
        XCTAssertEqual(posts, 0)
    }

    /// Cancelling and closing before loading yields cannot let a late preview start playing.
    func testCancelledPreviewCannotPlayAfterTheComposerIsDiscarded() async throws {
        let f = try await fixture()
        try await record(f)
        let draft = try XCTUnwrap(f.model.draft)
        let file = try await f.store.file(for: XCTUnwrap(draft.takeID), context: draft.context)
        f.model.preview()
        XCTAssertTrue(f.model.previewLoading)
        f.model.preview()
        XCTAssertFalse(f.model.previewLoading)
        XCTAssertNil(VoicePlayback.shared.requestedOwner)
        f.model.preview()
        f.model.disappear()
        await f.model.waitUntilClosed()
        XCTAssertFalse(f.model.previewLoading)
        XCTAssertNil(VoicePlayback.shared.owner)
        XCTAssertNil(VoicePlayback.shared.requestedOwner)
        XCTAssertNil(f.model.draft)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testReleaseFinalizesAndReviewsWithoutUploadOrPublication() async throws {
        let finish = VoiceTestGate()
        let f = try await fixture(recorder: ControlledVoiceRecorder(finishGate: finish))
        f.model.beginHold()
        try await eventually { f.model.phase == .recording }
        f.model.releaseHold()
        try await eventually { await f.recorder.finishes == 1 }
        XCTAssertEqual(f.model.phase, .finalizing)
        XCTAssertNil(f.model.draft?.transcript)
        XCTAssertFalse(f.model.canSend)
        await finish.open()
        try await eventually { f.model.phase == .ready }
        XCTAssertEqual(f.model.draft?.transcript, "Transcript from this take")
        XCTAssertNotNil(f.model.draft?.sha256)
        XCTAssertTrue(f.model.canSend)
        let uploads = await f.uploader.calls, sends = await f.publisher.events.count
        XCTAssertEqual(uploads, 0)
        XCTAssertEqual(sends, 0)
    }

    func testExplicitPostRetainsReceiptAndReusesExactEventOnRetry() async throws {
        let f = try await fixture()
        try await record(f)
        await f.model.send()
        let pending = try XCTUnwrap(f.model.draft)
        XCTAssertEqual(pending.phase, .retryable)
        XCTAssertNotNil(pending.eventJSON)
        XCTAssertNotNil(pending.receipt)
        XCTAssertTrue(pending.acceptedRelays.isEmpty)
        await f.model.send()
        let events = await f.publisher.events, uploads = await f.uploader.calls
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0], events[1])
        XCTAssertEqual(uploads, 1)
        let saved = try await f.store.load(context: pending.context)
        XCTAssertEqual(saved?.eventJSON, pending.eventJSON)
    }

    func testUnsupportedLocaleAndDeniedMicrophoneKeepTextUsable() async throws {
        let unsupported = try await fixture(transcriber: ControlledVoiceTranscriber(supported: false))
        unsupported.model.beginHold()
        try await eventually { !unsupported.model.busy }
        let starts = await unsupported.recorder.starts
        XCTAssertEqual(starts, 0)
        XCTAssertNotNil(unsupported.model.error)
        unsupported.model.releaseHold()
        unsupported.model.changeMode(.text)
        XCTAssertEqual(unsupported.model.mode, .text)
        let denied = try await fixture(recorder: ControlledVoiceRecorder(denied: true))
        denied.model.beginHold()
        try await eventually { !denied.model.busy }
        XCTAssertNotNil(denied.model.error)
        XCTAssertNil(denied.model.draft?.transcript)
        denied.model.releaseHold()
        denied.model.changeMode(.text)
        XCTAssertEqual(denied.model.mode, .text)
    }

    func testOfflineTranscriptionFailureKeepsTheFinalizedRecording() async throws {
        let f = try await fixture(transcriber: ControlledVoiceTranscriber(fails: true))
        try await record(f)
        let draft = try XCTUnwrap(f.model.draft)
        let file = try await f.store.file(for: XCTUnwrap(draft.takeID), context: draft.context)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertNil(draft.transcript)
        XCTAssertNotNil(f.model.error)
        XCTAssertFalse(f.model.canSend)
        await f.transcriber.setFailure(false)
        f.model.retryTranscription()
        try await eventually { f.model.phase == .ready }
        XCTAssertTrue(f.model.canSend)
        XCTAssertEqual(f.model.draft?.takeID, draft.takeID)
    }

    func testModeChangeDuringSpeechIgnoresALateTranscriptAndRetainsTake() async throws {
        let speech = VoiceTestGate()
        let f = try await fixture(transcriber: ControlledVoiceTranscriber(gate: speech))
        f.model.beginHold()
        try await eventually { f.model.phase == .recording }
        f.model.releaseHold()
        try await eventually { await f.transcriber.calls == 1 }
        let take = f.model.draft?.takeID
        f.model.changeMode(.text)
        await speech.open()
        try await eventually { !f.model.busy }
        XCTAssertEqual(f.model.mode, .text)
        XCTAssertEqual(f.model.draft?.takeID, take)
        XCTAssertNil(f.model.draft?.transcript)
        let uploads = await f.uploader.calls
        XCTAssertEqual(uploads, 0)
    }

    func testReleasedHoldCannotStartRecordingAfterLatePermissionCallback() async throws {
        let permission = VoiceTestGate()
        let f = try await fixture(recorder: ControlledVoiceRecorder(startGate: permission))
        f.model.beginHold()
        try await eventually { await f.recorder.starts == 1 }
        f.model.releaseHold()
        await permission.open()
        try await eventually { !f.model.busy }
        let finishes = await f.recorder.finishes, calls = await f.transcriber.calls
        XCTAssertEqual(finishes, 1)
        XCTAssertEqual(calls, 0)
        XCTAssertNotEqual(f.model.phase, .recording)
        XCTAssertNil(f.model.draft?.pendingTakeID)
        XCTAssertFalse(f.model.needsDiscardConfirmation)
    }

    func testInterruptionFinalizesWithoutTranscribingAndReplacementWaitsForWriter() async throws {
        let finish = VoiceTestGate()
        let f = try await fixture(recorder: ControlledVoiceRecorder(finishGate: finish))
        f.model.beginHold()
        try await eventually { f.model.phase == .recording }
        f.model.suspend()
        f.model.beginHold()
        XCTAssertEqual(f.model.phase, .finalizing)
        let starts = await f.recorder.starts
        XCTAssertEqual(starts, 1)
        await finish.open()
        try await eventually { !f.model.busy }
        XCTAssertNotNil(f.model.draft?.takeID)
        XCTAssertNil(f.model.draft?.transcript)
    }

    func testAccountChangeDuringUploadRejectsLateReceiptWithoutSigningOrSending() async throws {
        let upload = VoiceTestGate()
        let f = try await fixture(uploader: ControlledVoiceUploader(gate: upload))
        try await record(f)
        let sending = Task { await f.model.send() }
        try await eventually { await f.uploader.calls == 1 }
        f.state.voiceLifetime.invalidate()
        await upload.open()
        await sending.value
        let draft = try XCTUnwrap(f.model.draft)
        XCTAssertNil(draft.receipt)
        XCTAssertNil(draft.eventJSON)
        let sent = await f.publisher.events
        XCTAssertTrue(sent.isEmpty)
        let saved = try await f.store.load(context: draft.context)
        XCTAssertEqual(saved?.receipt, draft.receipt)
    }

    func testReopeningWaitsForDismissedComposersFinalizationAndStartsEmpty() async throws {
        let finish = VoiceTestGate()
        let f = try await fixture(recorder: ControlledVoiceRecorder(finishGate: finish))
        f.model.beginHold()
        try await eventually { f.model.phase == .recording }
        f.model.disappear()
        let reopened = VoiceComposerModel(state: f.state, action: .posting(.none), store: f.store,
                                          recorder: f.recorder, transcriber: f.transcriber, uploader: f.uploader, publisher: f.publisher)
        reopened.changeMode(.audio)
        XCTAssertEqual(reopened.phase, .loading)
        await finish.open()
        try await eventually { reopened.draft != nil && !reopened.busy }
        XCTAssertNil(reopened.draft?.transcript)
        XCTAssertNil(reopened.draft?.takeID)
        reopened.disappear()
        await reopened.waitUntilClosed()
    }

    func testClosingCannotBeReopenedWithOldAudio() async throws {
        let f = try await fixture()
        try await record(f)
        let old = try XCTUnwrap(f.model.draft)
        let file = try await f.store.file(for: XCTUnwrap(old.takeID), context: old.context)
        f.model.disappear()
        f.model.load()
        await f.model.waitUntilClosed()
        XCTAssertNil(f.model.draft)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        f.model.changeMode(.audio)
        try await eventually { f.model.draft != nil && !f.model.busy }
        XCTAssertNotEqual(f.model.draft?.id, old.id)
        XCTAssertNil(f.model.draft?.takeID)
        XCTAssertNil(f.model.draft?.transcript)
        XCTAssertFalse(f.model.canSend)
    }

    func testRapidFormatChangesAndSuspensionDoNotCancelEmptyAudioPreparation() async throws {
        let f = try await fixture()
        for _ in 0..<10 {
            let closed = await f.model.discardAndClose()
            XCTAssertTrue(closed)
            f.model.changeMode(.audio)
            XCTAssertEqual(f.model.phase, .loading)
            // No actor yield: preparation has not finished before format/background changes.
            f.model.changeMode(.text)
            f.model.suspend()
            f.model.changeMode(.audio)
            try await eventually { f.model.draft != nil && !f.model.busy }
            XCTAssertEqual(f.model.mode, .audio)
            XCTAssertTrue(f.model.canEditAttachments)
            XCTAssertNil(f.model.draft?.takeID)
            XCTAssertFalse(f.model.canSend)
        }
        try await record(f)
        XCTAssertTrue(f.model.canSend)
        let uploads = await f.uploader.calls, sends = await f.publisher.events.count
        XCTAssertEqual(uploads, 0)
        XCTAssertEqual(sends, 0)
    }

    func testStoreRestartHasNoRestorableAudioOrAutomaticPublication() async throws {
        let f = try await fixture()
        try await record(f)
        await f.model.send()
        let old = try XCTUnwrap(f.model.draft)
        XCTAssertNotNil(old.eventJSON)
        XCTAssertTrue(f.model.requestDismiss()) // Already submitted; closing is not retraction.
        let closed = await f.model.discardAndClose()
        XCTAssertTrue(closed)
        let restarted = VoiceDraftStore(root: f.root)
        let restored = await restarted.load(context: old.context)
        XCTAssertNil(restored)
        let uploads = await f.uploader.calls, events = await f.publisher.events
        XCTAssertEqual(uploads, 1)
        XCTAssertEqual(events.count, 1)
    }

    func testDiscardConfirmationKeepsEditingOrDeletesOnlyOnConfirmation() async throws {
        let f = try await fixture()
        XCTAssertTrue(f.model.requestDismiss())
        try await record(f)
        f.model.addMention(test_pubkey)
        XCTAssertTrue(f.model.addLink("https://example.com/article"))
        let draft = try XCTUnwrap(f.model.draft)
        let file = try await f.store.file(for: XCTUnwrap(draft.takeID), context: draft.context)
        XCTAssertFalse(f.model.requestDismiss())
        XCTAssertTrue(f.model.confirmingDiscard)
        f.model.keepEditing()
        XCTAssertFalse(f.model.confirmingDiscard)
        XCTAssertEqual(f.model.draft, draft)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        f.model.changeMode(.text)
        XCTAssertFalse(f.model.requestDismiss()) // Switching format cannot bypass confirmation.
        let closed = await f.model.discardAndClose()
        XCTAssertTrue(closed)
        XCTAssertNil(f.model.draft)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let current = await f.store.load(context: draft.context)
        XCTAssertNil(current)
    }

    func testTrashReleaseWaitsForWriterAndNeverTranscribesThenAllowsNewTake() async throws {
        let finish = VoiceTestGate()
        let f = try await fixture(recorder: ControlledVoiceRecorder(finishGate: finish))
        f.model.beginHold()
        try await eventually { f.model.phase == .recording }
        let old = try XCTUnwrap(f.model.draft)
        let file = try await f.store.file(for: XCTUnwrap(old.pendingTakeID), context: old.context)
        f.model.releaseHold(discard: true)
        f.model.releaseHold()
        f.model.beginHold()
        XCTAssertEqual(f.model.phase, .discarding)
        await finish.open()
        try await eventually { !f.model.busy }
        let finishes = await f.recorder.finishes, transcriptions = await f.transcriber.calls
        XCTAssertEqual(finishes, 1)
        XCTAssertEqual(transcriptions, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(f.model.needsDiscardConfirmation)
        try await record(f)
        XCTAssertNotEqual(f.model.draft?.takeID, old.pendingTakeID)
        XCTAssertEqual(f.model.draft?.transcript, "Transcript from this take")
    }

    func testDiscardDuringFinalizationDoesNotDoubleFinishOrTranscribe() async throws {
        let finish = VoiceTestGate()
        let f = try await fixture(recorder: ControlledVoiceRecorder(finishGate: finish))
        f.model.beginHold()
        try await eventually { f.model.phase == .recording }
        let old = try XCTUnwrap(f.model.draft)
        let file = try await f.store.file(for: XCTUnwrap(old.pendingTakeID), context: old.context)
        f.model.releaseHold()
        try await eventually { await f.recorder.finishes == 1 }
        f.model.discard()
        await finish.open()
        try await eventually { !f.model.busy }
        let finishes = await f.recorder.finishes, transcriptions = await f.transcriber.calls
        XCTAssertEqual(finishes, 1)
        XCTAssertEqual(transcriptions, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertNil(f.model.draft?.takeID)
    }

    func testDiscardRejectsLateTranscriptAndUploadResults() async throws {
        let speech = VoiceTestGate()
        let spoken = try await fixture(transcriber: ControlledVoiceTranscriber(gate: speech))
        spoken.model.beginHold()
        try await eventually { spoken.model.phase == .recording }
        spoken.model.releaseHold()
        try await eventually { await spoken.transcriber.calls == 1 }
        let oldID = spoken.model.draft?.id
        spoken.model.discard()
        await speech.open()
        try await eventually { !spoken.model.busy }
        XCTAssertNotEqual(spoken.model.draft?.id, oldID)
        XCTAssertNil(spoken.model.draft?.transcript)

        let upload = VoiceTestGate()
        let f = try await fixture(uploader: ControlledVoiceUploader(gate: upload))
        try await record(f)
        let old = try XCTUnwrap(f.model.draft)
        let file = try await f.store.file(for: XCTUnwrap(old.takeID), context: old.context)
        let sending = Task { await f.model.send() }
        try await eventually { await f.uploader.calls == 1 }
        f.model.discard()
        await upload.open()
        await sending.value
        try await eventually { !f.model.busy }
        XCTAssertNil(f.model.draft?.receipt)
        XCTAssertNil(f.model.draft?.eventJSON)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let events = await f.publisher.events
        XCTAssertTrue(events.isEmpty)
    }

    private func photo() -> Data {
        UIGraphicsImageRenderer(size: CGSize(width: 20, height: 10)).jpegData(withCompressionQuality: 0.9) { context in
            UIColor.blue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 20, height: 10))
        }
    }

    func testAttachmentsCanBeAddedRemovedAndPublishedAfterRecording() async throws {
        let f = try await fixture()
        try await record(f)
        let take = f.model.draft?.takeID
        let composition = try XCTUnwrap(f.model.draft?.id)
        let data = photo()
        f.model.addPhotos([{ data }, { data }], compositionID: composition)
        XCTAssertFalse(f.model.canSend)
        try await eventually { !f.model.busy }
        XCTAssertEqual(f.model.attachments.photos.count, 2)
        let removed = try XCTUnwrap(f.model.attachments.photos.first)
        let context = try XCTUnwrap(f.model.draft?.context)
        let removedFile = try await f.store.photoFile(for: removed.id, context: context)
        f.model.removePhoto(removed.id)
        try await eventually { !f.model.busy }
        XCTAssertFalse(FileManager.default.fileExists(atPath: removedFile.path))
        f.model.addMention(test_pubkey)
        f.model.removeMention(test_pubkey.hex())
        XCTAssertTrue(f.model.attachments.mentions.isEmpty)
        f.model.addMention(test_pubkey)
        XCTAssertTrue(f.model.addLink("https://example.com/removed"))
        f.model.removeLink("https://example.com/removed")
        XCTAssertTrue(f.model.attachments.links.isEmpty)
        XCTAssertTrue(f.model.addLink("https://example.com/article"))
        XCTAssertFalse(f.model.addLink("javascript:alert(1)"))
        XCTAssertEqual(f.model.draft?.takeID, take)
        await f.model.send()
        let pending = try XCTUnwrap(f.model.draft)
        let event = try VoiceEventBuilder.pendingEvent(pending)
        XCTAssertTrue(event.content.contains("nostr:" + test_pubkey.npub))
        XCTAssertTrue(event.content.contains("https://example.com/article"))
        XCTAssertEqual(event.tags.strings().filter { $0.first == "imeta" }.count, 1)
        XCTAssertEqual(event_image_metadata(ev: event).count, 1)
        XCTAssertEqual(try VoiceMediaReference(tags: event.tags.strings()).sha256, pending.sha256)
    }

    func testDismissDuringPhotoLoadingCannotRestoreAttachments() async throws {
        let f = try await fixture()
        let gate = VoiceTestGate()
        addTeardownBlock { await gate.open() }
        let data = photo()
        let id = try XCTUnwrap(f.model.draft?.id)
        f.model.addPhotos([{ await gate.wait(); return data }], compositionID: id)
        f.model.disappear()
        await gate.open()
        await f.model.waitUntilClosed()
        XCTAssertNil(f.model.draft)
        XCTAssertTrue(f.model.photoPreviews.isEmpty)
        f.model.changeMode(.audio)
        try await eventually { f.model.draft != nil && !f.model.busy }
        f.model.addPhotos([{ data }], compositionID: id) // Stale picker callback.
        XCTAssertTrue(f.model.attachments.isEmpty)
    }

    func testCleanupFailureKeepsComposerOpenAndAllowsRetry() async throws {
        let f = try await fixture()
        try await record(f)
        let id = f.model.draft?.id
        // Replace the fixture's directory with a file to force a real filesystem failure.
        try FileManager.default.removeItem(at: f.root)
        try Data("obstruction".utf8).write(to: f.root)
        let failed = await f.model.discardAndClose()
        XCTAssertFalse(failed)
        XCTAssertEqual(f.model.draft?.id, id)
        XCTAssertEqual(f.model.mode, .audio)
        XCTAssertNotNil(f.model.error)
        try FileManager.default.removeItem(at: f.root)
        let retried = await f.model.discardAndClose()
        XCTAssertTrue(retried)
        XCTAssertNil(f.model.draft)
    }

    func testRecordingGestureUsesFinalPositionAndCancelsExactlyOnce() {
        var gesture = VoiceRecordingGesture()
        let mic = CGPoint(x: 38, y: 38)
        let trash = VoiceRecordingGesture.trashCenter
        gesture.begin()
        gesture.move(to: trash)
        XCTAssertTrue(gesture.isOverTrash)
        gesture.move(to: mic)
        XCTAssertFalse(gesture.isOverTrash)
        XCTAssertEqual(gesture.end(at: mic), .finish)
        XCTAssertNil(gesture.end(at: trash))
        gesture.begin()
        XCTAssertEqual(gesture.end(at: trash), .discard)
        gesture.begin()
        XCTAssertEqual(gesture.end(at: mic, cancelled: true), .discard)
    }
}

private struct VoiceComposerFixture {
    let model: VoiceComposerModel
    let state: DamusState
    let store: VoiceDraftStore
    let root: URL
    let recorder: ControlledVoiceRecorder
    let transcriber: ControlledVoiceTranscriber
    let uploader: ControlledVoiceUploader
    let publisher: ControlledVoicePublisher
}

private actor VoiceTestGate {
    private var opened = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func wait() async {
        guard !opened else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
    func open() { opened = true; let pending = waiters; waiters.removeAll(); pending.forEach { $0.resume() } }
}

private actor ControlledVoiceRecorder: VoiceRecording {
    let startGate: VoiceTestGate?
    let finishGate: VoiceTestGate?
    let denied: Bool
    private var url: URL?
    private(set) var starts = 0
    private(set) var finishes = 0
    init(startGate: VoiceTestGate? = nil, finishGate: VoiceTestGate? = nil, denied: Bool = false) {
        self.startGate = startGate; self.finishGate = finishGate; self.denied = denied
    }
    func start(to url: URL) async throws {
        starts += 1
        await startGate?.wait()
        if denied { throw VoiceFailure("Microphone permission denied") }
        self.url = url
    }
    func finish() async throws {
        finishes += 1
        await finishGate?.wait()
        guard let url else { throw VoiceFailure("No writer") }
        try Self.writeAudio(url)
        self.url = nil
    }
    private static func writeAudio(_ url: URL) throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16_000))
        buffer.frameLength = 16_000
        for i in 0..<16_000 { buffer.floatChannelData![0][i] = Float(sin(Double(i) * 2 * .pi * 440 / 16_000) * 0.1) }
        let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC,
                                                              AVSampleRateKey: 16_000, AVNumberOfChannelsKey: 1, AVEncoderBitRateKey: 48_000])
        try file.write(from: buffer)
    }
}

private actor ControlledVoiceTranscriber: VoiceTranscribing {
    let supported: Bool
    let gate: VoiceTestGate?
    private var fails: Bool
    private(set) var calls = 0
    init(supported: Bool = true, gate: VoiceTestGate? = nil, fails: Bool = false) {
        self.supported = supported; self.gate = gate; self.fails = fails
    }
    func supports(locale: String) async -> Bool { supported }
    func setFailure(_ value: Bool) { fails = value }
    func transcribe(_ url: URL, locale: String) async throws -> String {
        calls += 1
        await gate?.wait()
        if fails { throw VoiceFailure("On-device recognizer unavailable while offline") }
        return "Transcript from this take"
    }
}

private actor ControlledVoiceUploader: VoiceUploading {
    let gate: VoiceTestGate?
    private(set) var calls = 0
    init(gate: VoiceTestGate? = nil) { self.gate = gate }
    func upload(file: URL, server: String, keypair: FullKeypair, lifetime: VoiceAccountLifetime) async throws -> VoiceUploadReceipt {
        calls += 1
        await gate?.wait()
        let data = try Data(contentsOf: file)
        let reference = try VoiceMediaReference(url: "https://blossom.band/opaque?saved=receipt",
                                               sha256: VoiceAudioFiles.digest(data), mimeType: "audio/mp4", duration: nil)
        return VoiceUploadReceipt(server: "https://blossom.band", reference: reference, size: data.count)
    }
}

private actor ControlledVoicePublisher: VoicePublishing {
    let store: VoiceDraftStore
    private(set) var events: [String] = []
    init(store: VoiceDraftStore) { self.store = store }
    func publish(_ draft: VoiceDraft, state: DamusState) async throws {
        _ = try VoiceEventBuilder.pendingEvent(draft)
        try await store.requireCurrentEvent(draft)
        events.append(try XCTUnwrap(draft.eventJSON))
        try await store.recordDelivery(.noRelays, for: draft)
    }
}

private actor ControlledVoicePhotoUploader: VoicePhotoUploading {
    func uploadPhoto(file: URL, server: String, keypair: FullKeypair, lifetime: VoiceAccountLifetime) async throws -> String {
        let bytes = try Data(contentsOf: file)
        return "https://blossom.band/" + VoiceAudioFiles.digest(bytes) + ".jpg"
    }
}
