import AVFoundation
import XCTest
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
                                       transcriber: transcriber, uploader: uploader, publisher: publisher)
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

    func testExplicitPostPersistsReceiptAndReusesExactEventOnRetry() async throws {
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
        XCTAssertNotNil(f.model.draft?.pendingTakeID)
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

    func testAccountChangeDuringUploadRetainsReceiptWithoutSigningOrSending() async throws {
        let upload = VoiceTestGate()
        let f = try await fixture(uploader: ControlledVoiceUploader(gate: upload))
        try await record(f)
        let sending = Task { await f.model.send() }
        try await eventually { await f.uploader.calls == 1 }
        f.state.voiceLifetime.invalidate()
        await upload.open()
        await sending.value
        let draft = try XCTUnwrap(f.model.draft)
        XCTAssertNotNil(draft.receipt)
        XCTAssertNil(draft.eventJSON)
        let sent = await f.publisher.events
        XCTAssertTrue(sent.isEmpty)
        let saved = try await f.store.load(context: draft.context)
        XCTAssertEqual(saved?.receipt, draft.receipt)
    }

    func testReopeningWaitsForDismissedComposersFinalizationAndRecoversTake() async throws {
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
        try await eventually { reopened.draft?.takeID != nil && !reopened.busy }
        XCTAssertNil(reopened.draft?.transcript)
        reopened.disappear()
    }

    func testSameComposerCanReappearDuringAndAfterClosing() async throws {
        let f = try await fixture()
        try await record(f)
        let saved = try XCTUnwrap(f.model.draft)
        f.model.disappear()
        f.model.load()
        await f.model.waitUntilClosed()
        XCTAssertEqual(f.model.draft?.id, saved.id)
        XCTAssertTrue(f.model.canSend)
        f.model.disappear()
        await f.model.waitUntilClosed()
        XCTAssertNil(f.model.draft)
        f.model.load()
        try await eventually { f.model.draft != nil && !f.model.busy }
        XCTAssertEqual(f.model.draft?.takeID, saved.takeID)
        XCTAssertEqual(f.model.draft?.transcript, saved.transcript)
        XCTAssertTrue(f.model.canSend)
    }

    func testPendingPublicationAndReceiptSurviveStoreRestart() async throws {
        let f = try await fixture()
        try await record(f)
        await f.model.send()
        let saved = try XCTUnwrap(f.model.draft)
        f.model.disappear()
        let restartedStore = VoiceDraftStore(root: f.root)
        let restartedPublisher = ControlledVoicePublisher(store: restartedStore)
        let reopened = VoiceComposerModel(state: f.state, action: .posting(.none), store: restartedStore,
                                          recorder: f.recorder, transcriber: f.transcriber, uploader: f.uploader, publisher: restartedPublisher)
        reopened.changeMode(.audio)
        try await eventually { reopened.draft != nil && !reopened.busy }
        XCTAssertEqual(reopened.draft?.eventJSON, saved.eventJSON)
        await reopened.send()
        let uploads = await f.uploader.calls, events = await restartedPublisher.events
        XCTAssertEqual(uploads, 1)
        XCTAssertEqual(events, [saved.eventJSON!])
        reopened.disappear()
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
        _ = try VoiceEventBuilder.restoredEvent(draft)
        try await store.requireSavedEvent(draft)
        events.append(try XCTUnwrap(draft.eventJSON))
        try await store.recordDelivery(.noRelays, for: draft)
    }
}
