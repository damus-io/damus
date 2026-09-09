import Foundation
import SwiftUI
import Speech

/// One sheet owns one immutable account/context and one asynchronous operation at a time.
@MainActor
final class VoiceComposerModel: ObservableObject {
    enum Mode: String, CaseIterable { case text, audio }
    enum Phase { case idle, loading, requestingPermission, recording, finalizing, transcribing, ready, uploading, publishing, failed }
    @Published var mode: Mode = .text
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var draft: VoiceDraft?
    @Published private(set) var error: String?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published var locale = Locale.current.identifier
    let state: DamusState
    let action: PostAction
    private let store: VoiceDraftStore
    private let recorder: any VoiceRecording
    private let transcriber: any VoiceTranscribing
    private let uploader: any VoiceUploading
    private let publisher: any VoicePublishing
    private var operation: Task<Void, Never>?
    private var lease: VoiceDraftLease?
    private var closing: Task<Void, Never>?
    private var meter: Task<Void, Never>?
    private var monitor: Task<Void, Never>?
    private var holding = false
    private var visible = true
    private let recordingIdentity = UUID()

    init(state: DamusState, action: PostAction, store: VoiceDraftStore = .shared,
         recorder: any VoiceRecording = AppleVoiceRecorder.shared,
         transcriber: any VoiceTranscribing = AppleVoiceTranscriber(),
         uploader: any VoiceUploading = VoiceBlossomUploader(),
         publisher: (any VoicePublishing)? = nil) {
        self.state = state
        self.action = action
        self.store = store
        self.recorder = recorder
        self.transcriber = transcriber
        self.uploader = uploader
        self.publisher = publisher ?? VoicePublisher(store: store)
    }

    var supportsAction: Bool {
        guard !Bundle.main.bundlePath.hasSuffix(".appex"),
              state.keypair.to_full() != nil, state.voiceLifetime.isActive else { return false }
        switch action {
        case .posting: return true
        case .replying_to(let event), .quoting(let event): return !event.is_rumor && event.known_kind?.isPost == true
        case .sharing, .highlighting: return false
        }
    }

    var busy: Bool {
        switch phase {
        case .loading, .requestingPermission, .recording, .finalizing, .transcribing, .uploading, .publishing: return true
        case .idle, .ready, .failed: return false
        }
    }

    var canSend: Bool {
        guard mode == .audio, supportsAction, visible, lease != nil, !busy, let draft else { return false }
        if draft.eventJSON != nil { return draft.phase != .accepted }
        return draft.pendingTakeID == nil && draft.takeID != nil && draft.transcript?.isEmpty == false
            && (draft.receipt != nil || (try? VoiceBlossomUploader.origin(state.settings.voice_blossom_server)) != nil)
    }

    var status: String {
        switch phase {
        case .loading: return "Loading saved recording…"
        case .requestingPermission: return "Preparing microphone…"
        case .recording: return "Recording — release to finish"
        case .finalizing: return "Finishing recording…"
        case .transcribing: return "Transcribing on this device…"
        case .uploading: return "Uploading recording…"
        case .publishing: return "Saving and queuing post…"
        default:
            switch draft?.phase {
            case .queued, .dispatched: return "Saved. Waiting for a relay to accept this post."
            case .accepted: return "Accepted by \(draft?.acceptedRelays.count ?? 0) relay(s)."
            case .rejected: return "Rejected by a relay. Your post is saved for retry."
            case .retryable: return "Post saved. Delivery needs a retry."
            default: return draft?.takeID == nil ? "Hold the microphone to record" : "Review your recording before posting"
            }
        }
    }

    /// Load is opt-in on opening Audio; it never starts recording, upload, or publication.
    func load() {
        visible = true
        startMonitoring()
        guard supportsAction, draft == nil, !busy else { return }
        phase = .loading
        operation = Task {
            do {
                let action = self.action
                let account = state.pubkey.hex()
                let context = try await Task.detached { () throws -> VoiceContext in
                    let context: VoiceContext
                    switch action {
                    case .posting(let target):
                        let recipient: String?
                        if case .user(let pubkey) = target, pubkey.hex() != account { recipient = pubkey.hex() }
                        else { recipient = nil }
                        context = VoiceContext(account: account, kind: .post, targetID: nil, targetJSON: nil, recipient: recipient)
                    case .replying_to(let parent): context = VoiceContext(account: account, kind: .reply, targetID: parent.id.hex(), targetJSON: event_to_json(ev: parent))
                    case .quoting(let parent): context = VoiceContext(account: account, kind: .quote, targetID: parent.id.hex(), targetJSON: event_to_json(ev: parent))
                    default: throw VoiceFailure("Audio is unavailable for this composition.")
                    }
                    _ = try context.target()
                    return context
                }.value
                try checkActive()
                lease = try await store.acquire(context: context)
                try checkActive()
                var saved = try await store.load(context: context) ?? VoiceDraft(context: context, locale: locale)
                if let pending = saved.pendingTakeID {
                    // A terminated app may leave a finalized partial take. Validate before adopting it.
                    let file = try await store.file(for: pending, context: saved.context)
                    do {
                        let audio = try await VoiceAudioFiles.shared.inspect(file)
                        let previous = saved.takeID
                        saved.takeID = pending
                        saved.pendingTakeID = nil
                        saved.transcript = nil
                        saved.duration = audio.duration
                        saved.sha256 = audio.sha256
                        saved.size = audio.size
                        saved.receipt = nil
                        saved.lastError = "Recovered an interrupted recording. Listen, then retry transcription."
                        saved = try await save(saved)
                        if let previous { try? await store.removeTake(previous, context: saved.context) }
                    } catch {
                        saved.lastError = "An interrupted take could not be opened. Your previous recording is preserved; discard or record again."
                    }
                }
                try checkActive()
                self.draft = saved
                self.locale = saved.locale
                self.error = saved.lastError
                phase = saved.takeID == nil ? .idle : .ready
                startMonitoring()
            } catch {
                lease = nil
                finishFailure(error)
            }
        }
    }

    /// Mode changes preserve both drafts. A running writer is finalized, never read mid-write.
    func changeMode(_ value: Mode) {
        mode = value
        if value == .audio { load(); return }
        suspend()
    }

    func beginHold() {
        guard mode == .audio, supportsAction, visible, lease != nil, !holding, !busy,
              var draft, draft.eventJSON == nil else { return }

        holding = true
        error = nil
        phase = .requestingPermission
        do { try VoicePlayback.shared.beginRecording(owner: recordingIdentity, video: state.video) }
        catch { finishFailure(error); return }
        let take = UUID()
        let abandoned = draft.pendingTakeID
        draft.pendingTakeID = take
        draft.locale = locale
        operation = Task {
            do {
                guard await transcriber.supports(locale: draft.locale) else {
                    throw VoiceFailure("On-device transcription is unavailable for this language on this device. Text posts remain available.")
                }
                try checkActive()
                draft = try await save(draft)
                self.draft = draft
                if let abandoned { try? await store.removeTake(abandoned, context: draft.context) }
                let file = try await store.file(for: take, context: draft.context)
                try checkActive()
                try await recorder.start(to: file)
                do { try checkActive() } catch { try? await recorder.finish(); throw error }
                guard holding else {
                    try? await recorder.finish()
                    finishFailure(CancellationError())
                    return
                }
                phase = .recording
                let started = Date()
                meter = Task {
                    while !Task.isCancelled, phase == .recording {
                        elapsed = Date().timeIntervalSince(started)
                        if elapsed >= VoiceLimits.recordingDuration { releaseHold(); return }
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                }
            } catch { finishFailure(error) }
        }
    }

    /// Releasing only finalizes and transcribes. It has no upload or relay path.
    func releaseHold() {
        holding = false
        if phase == .requestingPermission {
            operation?.cancel()
            return
        }
        guard phase == .recording else { return }
        finishRecording(transcribe: true)
    }

    private func finishRecording(transcribe: Bool) {
        meter?.cancel()
        holding = false
        phase = .finalizing
        operation = Task {
            do {
                var writerError: Error?
                do { try await recorder.finish() } catch { writerError = error }
                VoicePlayback.shared.endRecording(owner: recordingIdentity)
                guard var saved = draft, let pending = saved.pendingTakeID else { throw VoiceFailure("The recording no longer belongs to this draft.") }
                let file = try await store.file(for: pending, context: saved.context)
                let audio = try await VoiceAudioFiles.shared.inspect(file)
                let previous = saved.takeID
                saved.takeID = pending
                saved.pendingTakeID = nil
                saved.transcript = nil
                saved.duration = audio.duration
                saved.sha256 = audio.sha256
                saved.size = audio.size
                saved.receipt = nil
                saved.lastError = writerError?.localizedDescription
                saved = try await save(saved)
                draft = saved
                if let previous { try? await store.removeTake(previous, context: saved.context) }
                if transcribe, writerError == nil, mode == .audio, visible, state.voiceLifetime.isActive {
                    try await transcribeCurrent()
                } else {
                    error = saved.lastError ?? "Recording saved. Retry transcription when ready."
                    phase = .ready
                }
            } catch { finishFailure(error) }
        }
    }

    func retryTranscription() {
        guard mode == .audio, visible, lease != nil, !busy, draft?.takeID != nil, draft?.eventJSON == nil else { return }
        phase = .transcribing
        operation = Task {
            do { try await transcribeCurrent() } catch { finishFailure(error) }
        }
    }

    private func transcribeCurrent() async throws {
        guard var saved = draft, let take = saved.takeID else { throw VoiceFailure("Record a take first.") }
        try checkActive()
        phase = .transcribing
        error = nil
        let file = try await store.file(for: take, context: saved.context)
        _ = try await VoiceAudioFiles.shared.inspect(file, expectedHash: saved.sha256)
        saved.locale = locale
        let text = try await transcriber.transcribe(file, locale: saved.locale)
        try checkActive()
        guard draft?.takeID == take, draft?.id == saved.id else { throw CancellationError() }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= 12_000 else {
            throw VoiceFailure("No usable transcript was produced. Listen to the saved recording and retry transcription.")
        }
        saved.transcript = text
        saved.lastError = nil
        saved = try await save(saved)
        draft = saved
        phase = .ready
    }

    /// Only the explicit Post button calls this method. Persist each irreversible handoff first.
    func send() async {
        guard canSend, var saved = draft, let keypair = state.keypair.to_full() else { return }
        error = nil
        phase = saved.eventJSON == nil ? .uploading : .publishing
        operation = Task {
            do {
                try checkActive()
                if saved.eventJSON == nil {
                    guard let take = saved.takeID else { throw VoiceFailure("The recording is missing.") }
                    let file = try await store.file(for: take, context: saved.context)
                    let audio = try await VoiceAudioFiles.shared.inspect(file, expectedHash: saved.sha256)
                    guard audio.size == saved.size else { throw VoiceFailure("The saved recording changed.") }
                    if saved.receipt == nil {
                        saved.receipt = try await uploader.upload(file: file, server: state.settings.voice_blossom_server, keypair: keypair, lifetime: state.voiceLifetime)
                        // Even if the sheet closes at this instant, retain a successful upload receipt.
                        saved = try await save(saved)
                        draft = saved
                    }
                    try checkActive()
                    phase = .publishing
                    let snapshot = saved
                    let clientTag = state.clientTagComponents
                    let event = try await Task.detached { try VoiceEventBuilder.build(snapshot, keypair: keypair, clientTag: clientTag) }.value
                    try checkActive()
                    saved.eventJSON = event_to_json(ev: event)
                    saved.phase = .queued
                    saved = try await save(saved)
                    draft = saved
                }
                try checkActive()
                try await publisher.publish(saved, state: state)
                draft = try await store.load(context: saved.context) ?? saved
                phase = .ready
                error = draft?.lastError
                startMonitoring()
            } catch { finishFailure(error) }
        }
        await operation?.value
    }

    func preview() {
        guard mode == .audio, visible, lease != nil, !busy, let saved = draft, let take = saved.takeID else { return }
        if VoicePlayback.shared.owner == take.uuidString { VoicePlayback.shared.toggle(); return }
        do { try VoicePlayback.shared.beginRequest(owner: take.uuidString) }
        catch { finishFailure(error); return }
        phase = .loading
        operation = Task {
            do {
                let file = try await store.file(for: take, context: saved.context)
                let audio = try await VoiceAudioFiles.shared.inspect(file, expectedHash: saved.sha256)
                try checkActive()
                guard draft?.id == saved.id, draft?.takeID == take, mode == .audio else { throw CancellationError() }
                try VoicePlayback.shared.play(audio, owner: take.uuidString, video: state.video)
                phase = .ready
            } catch { finishFailure(error) }
        }
    }

    /// Release the recording only after persisted relay acceptance and the user's Done action.
    func finishAccepted() async -> Bool {
        guard !busy, let saved = draft, let lease, saved.phase == .accepted else { return false }
        phase = .loading
        do {
            try await store.discard(saved, lease: lease)
            draft = nil
            return true
        } catch { finishFailure(error); return false }
    }

    /// Explicit discard affects only this voice draft; the Text draft stays in Damus's draft store.
    func discard() {
        guard !busy, let saved = draft, let lease else { return }
        VoicePlayback.shared.stop()
        phase = .loading
        operation = Task {
            do {
                try await store.discard(saved, lease: lease)
                draft = VoiceDraft(context: saved.context, locale: locale)
                error = nil
                elapsed = 0
                phase = .idle
            } catch { finishFailure(error) }
        }
    }

    func suspend() {
        holding = false
        meter?.cancel()
        VoicePlayback.shared.stop()
        if phase == .recording { finishRecording(transcribe: false) }
        else if phase != .finalizing && !(phase == .loading && draft == nil && visible) { operation?.cancel() }
    }

    func disappear() {
        visible = false
        monitor?.cancel()
        suspend()
        guard closing == nil else { return }
        let finishing = operation
        closing = Task {
            await finishing?.value
            // Finalization and a late successful upload must persist before another sheet reads.
            if !visible {
                let releasedLease = lease
                // Clear this model's ownership before yielding; a reappearing sheet may load again.
                lease = nil
                draft = nil
                if let releasedLease { await store.release(context: releasedLease.context, owner: releasedLease.id) }
            }
            closing = nil
        }
    }

    /// Wait for writer finalization and durable handoff before releasing external resources.
    func waitUntilClosed() async { await closing?.value }

    private func save(_ value: VoiceDraft) async throws -> VoiceDraft {
        guard let lease else { throw CancellationError() }
        return try await store.save(value, lease: lease)
    }

    private func checkActive() throws {
        try Task.checkCancellation()
        guard state.voiceLifetime.isActive, visible else { throw CancellationError() }
    }

    private func finishFailure(_ failure: Error) {
        VoicePlayback.shared.endRecording(owner: recordingIdentity)
        if failure is CancellationError { error = draft?.takeID == nil ? nil : "Recording saved. Continue when ready." }
        else { error = failure.localizedDescription }
        phase = draft?.takeID == nil ? .idle : .failed
    }

    private func startMonitoring() {
        monitor?.cancel()
        guard visible, let context = draft?.context, draft?.eventJSON != nil else { return }
        monitor = Task {
            while !Task.isCancelled, visible, state.voiceLifetime.isActive {
                do {
                    if let saved = try await store.load(context: context), saved.id == draft?.id {
                        draft = saved
                        if !busy { error = saved.lastError }
                        if saved.phase == .accepted { return }
                    }
                    try await Task.sleep(nanoseconds: 1_000_000_000)
                } catch { return }
            }
        }
    }
}
