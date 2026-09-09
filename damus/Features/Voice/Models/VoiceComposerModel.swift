import Foundation
import SwiftUI
import UIKit

/// One sheet owns its temporary audio, attachments, and asynchronous operations.
@MainActor
final class VoiceComposerModel: ObservableObject {
    enum Mode: String, CaseIterable { case text, audio }
    enum Phase { case idle, loading, requestingPermission, recording, finalizing, transcribing, ready, uploading, publishing, discarding, failed }
    @Published var mode: Mode = .text
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var draft: VoiceDraft?
    @Published private(set) var error: String?
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var photoPreviews: [UUID: UIImage] = [:]
    @Published private(set) var previewLoading = false
    @Published private(set) var previewPosition: TimeInterval = 0
    private var previewTask: Task<Void, Never>?
    private var previewRequestID = UUID()
    @Published var confirmingDiscard = false
    @Published var locale = Locale.current.identifier
    let state: DamusState
    let action: PostAction
    private let store: VoiceDraftStore
    private let recorder: any VoiceRecording
    private let transcriber: any VoiceTranscribing
    private let uploader: any VoiceUploading
    private let photoUploader: any VoicePhotoUploading
    private let publisher: any VoicePublishing
    private var operation: Task<Void, Never>?
    private var lease: VoiceDraftLease?
    private var closing: Task<Bool, Never>?
    private var closingRequested = false
    private var meter: Task<Void, Never>?
    private var monitor: Task<Void, Never>?
    private var holding = false
    private var hoveringTrash = false
    private var writerOpen = false
    private var visible = true
    private let recordingIdentity = UUID()

    init(state: DamusState, action: PostAction, store: VoiceDraftStore = .shared,
         recorder: any VoiceRecording = AppleVoiceRecorder.shared,
         transcriber: any VoiceTranscribing = AppleVoiceTranscriber(),
         uploader: any VoiceUploading = VoiceBlossomUploader(),
         photoUploader: any VoicePhotoUploading = VoiceBlossomUploader(),
         publisher: (any VoicePublishing)? = nil) {
        self.state = state
        self.action = action
        self.store = store
        self.recorder = recorder
        self.transcriber = transcriber
        self.uploader = uploader
        self.photoUploader = photoUploader
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
        case .idle, .ready, .failed: return false
        default: return true
        }
    }

    var attachments: VoicePostAttachments { draft?.attachments ?? VoicePostAttachments() }
    var canEditAttachments: Bool { mode == .audio && visible && supportsAction && !busy && draft != nil && draft?.eventJSON == nil }
    var dismissalLocked: Bool { phase == .publishing || phase == .discarding }
    var needsDiscardConfirmation: Bool {
        guard draft?.eventJSON == nil else { return false }
        return draft?.takeID != nil || draft?.pendingTakeID != nil || !attachments.isEmpty
            || phase == .requestingPermission || phase == .recording
    }

    var canSend: Bool {
        guard mode == .audio, supportsAction, visible, lease != nil, !busy, let draft else { return false }
        if draft.eventJSON != nil { return draft.phase != .accepted }
        return draft.pendingTakeID == nil && draft.takeID != nil && draft.transcript?.isEmpty == false
            && (try? VoiceBlossomUploader.origin(state.settings.voice_blossom_server)) != nil
    }

    var status: String {
        switch phase {
        case .loading: return "Preparing audio post…"
        case .requestingPermission: return "Preparing microphone…"
        case .recording: return "Recording — slide left to discard"
        case .finalizing: return "Finishing recording…"
        case .transcribing: return "Transcribing on this device…"
        case .uploading: return "Uploading audio and photos…"
        case .publishing: return "Queuing post…"
        case .discarding: return "Discarding audio post…"
        default:
            switch draft?.phase {
            case .queued, .dispatched: return "Waiting for a relay to accept this post."
            case .accepted: return "Accepted by \(draft?.acceptedRelays.count ?? 0) relay(s)."
            case .rejected: return "A relay rejected this post. You can retry."
            case .retryable: return "Delivery needs a retry."
            default: return draft?.takeID == nil ? "Hold to record" : "Review recording"
            }
        }
    }

    /// Both Cancel and an attempted interactive dismissal use this decision before cleanup.
    func requestDismiss() -> Bool {
        guard !dismissalLocked else { return false }
        if needsDiscardConfirmation {
            confirmingDiscard = true
            return false
        }
        return true
    }

    /// Rejecting discard changes no composition state.
    func keepEditing() { confirmingDiscard = false }

    /// Audio begins with a new composition, even when the same context was used previously.
    func load() {
        guard closing == nil, supportsAction, draft == nil, !busy else { return }
        visible = true
        closingRequested = false
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
                let acquired = try await store.acquire(context: context)
                lease = acquired
                try checkActive()
                draft = VoiceDraft(context: context, locale: locale)
                phase = .idle
            } catch {
                // A cancelled acquisition must not leave this model waiting on its own lease.
                if let acquired = lease {
                    lease = nil
                    await store.release(context: acquired.context, owner: acquired.id)
                }
                finishFailure(error)
            }
        }
    }

    /// Switching formats retains the take only within this open composer.
    func changeMode(_ value: Mode) {
        guard !dismissalLocked else { return }
        mode = value
        if value == .audio { load(); return }
        suspend()
    }

    /// Start one owned writer. A permission callback cannot revive a cancelled hold.
    func beginHold() {
        guard mode == .audio, supportsAction, visible, lease != nil, !holding, !busy,
              var draft, draft.eventJSON == nil else { return }
        stopPreview()
        holding = true
        hoveringTrash = false
        error = nil
        elapsed = 0
        phase = .requestingPermission
        do { try VoicePlayback.shared.beginRecording(owner: recordingIdentity, video: state.video) }
        catch { holding = false; finishFailure(error); return }
        let take = UUID()
        draft.pendingTakeID = take
        draft.locale = locale
        self.draft = draft
        operation = Task {
            do {
                guard await transcriber.supports(locale: draft.locale) else {
                    throw VoiceFailure("On-device transcription is unavailable for this language on this device. Text posts remain available.")
                }
                try checkActive()
                self.draft = try await save(draft)
                let file = try await store.file(for: take, context: draft.context)
                try checkActive()
                try await recorder.start(to: file)
                writerOpen = true
                try checkActive()
                guard holding else { throw CancellationError() }
                phase = .recording
                let started = Date()
                meter = Task {
                    while !Task.isCancelled, phase == .recording {
                        elapsed = Date().timeIntervalSince(started)
                        if elapsed >= VoiceLimits.recordingDuration { releaseHold(discard: hoveringTrash); return }
                        try? await Task.sleep(nanoseconds: 100_000_000)
                    }
                }
            } catch {
                if writerOpen {
                    // finish() stops/releases the writer even when it reports an encoding error.
                    try? await recorder.finish()
                    writerOpen = false
                }
                holding = false
                if closing == nil, var current = self.draft, let lease {
                    current.pendingTakeID = nil
                    do {
                        self.draft = try await store.save(current, lease: lease)
                        try await store.removeTake(take, context: current.context)
                    } catch {
                        finishFailure(error)
                        return
                    }
                }
                finishFailure(error)
            }
        }
    }

    /// The release decision precedes finalization: trash never starts transcription or upload.
    func releaseHold(discard: Bool = false) {
        guard holding else { return }
        if discard || phase == .requestingPermission { cancelHold(); return }
        holding = false
        guard phase == .recording else { return }
        finishRecording(transcribe: true)
    }

    func updateTrashHover(_ overTrash: Bool) {
        if holding { hoveringTrash = overTrash }
    }

    /// Cancelled gestures and a release over trash share the same owned cleanup.
    func cancelHold() {
        guard holding || phase == .requestingPermission || phase == .recording else { return }
        _ = beginCleanup(close: false)
    }

    private func finishRecording(transcribe: Bool) {
        meter?.cancel()
        holding = false
        phase = .finalizing
        operation = Task {
            do {
                var writerError: Error?
                do { try await recorder.finish() } catch { writerError = error }
                writerOpen = false
                VoicePlayback.shared.endRecording(owner: recordingIdentity)
                try checkActive()
                guard var saved = draft, let pending = saved.pendingTakeID else { throw VoiceFailure("The recording no longer belongs to this composition.") }
                let file = try await store.file(for: pending, context: saved.context)
                let audio = try await VoiceAudioFiles.shared.inspect(file)
                try checkActive()
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
                if let previous { try await store.removeTake(previous, context: saved.context) }
                try checkActive()
                if transcribe, writerError == nil, mode == .audio {
                    try await transcribeCurrent()
                } else {
                    error = saved.lastError ?? "Retry transcription when ready."
                    phase = .ready
                }
            } catch { finishFailure(error) }
        }
    }

    func retryTranscription() {
        guard mode == .audio, visible, lease != nil, !busy, draft?.takeID != nil, draft?.eventJSON == nil else { return }
        stopPreview()
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
            throw VoiceFailure("No usable transcript was produced. Listen to this recording and retry transcription.")
        }
        saved.transcript = text
        saved.lastError = nil
        draft = try await save(saved)
        phase = .ready
    }

    /// Mentions and links edit only audio composition state, never Damus's text draft.
    func addMention(_ pubkey: Pubkey) {
        guard canEditAttachments else { return }
        var value = attachments
        guard !value.mentions.contains(pubkey.hex()), value.mentions.count < 100 else { return }
        value.mentions.append(pubkey.hex())
        draft?.attachments = value
    }

    func addLink(_ input: String) -> Bool {
        guard canEditAttachments else { return false }
        do {
            let url = try VoicePostAttachments.webURL(input)
            var value = attachments
            guard value.links.count < 20 else { throw VoiceFailure("A post can contain up to 20 web links.") }
            if !value.links.contains(url) { value.links.append(url) }
            draft?.attachments = value
            error = nil
            return true
        } catch { self.error = error.localizedDescription; return false }
    }

    func removeMention(_ hex: String) {
        guard canEditAttachments else { return }
        var value = attachments
        value.mentions.removeAll { $0 == hex }
        draft?.attachments = value
    }

    func removeLink(_ link: String) {
        guard canEditAttachments else { return }
        var value = attachments
        value.links.removeAll { $0 == link }
        draft?.attachments = value
    }

    /// The model owns picker loading too, so Post and discard cannot race an unfinished selection.
    func addPhotos(_ loaders: [() async throws -> Data], compositionID: UUID) {
        guard canEditAttachments, draft?.id == compositionID, let context = draft?.context else { return }
        guard !loaders.isEmpty, attachments.photos.count + loaders.count <= 8 else {
            error = "A post can contain up to 8 photos."
            return
        }
        phase = .loading
        operation = Task {
            do {
                for load in loaders {
                    let data = try await load()
                    try checkActive()
                    let id = UUID()
                    let file = try await store.photoFile(for: id, context: context)
                    let prepared = try await VoicePhotoFiles.shared.prepare(data, to: file)
                    try checkActive()
                    guard draft?.id == compositionID else { throw CancellationError() }
                    var value = attachments
                    value.photos.append(VoicePhotoAttachment(id: id, url: nil, dim: prepared.dim, blurhash: prepared.blurhash))
                    draft?.attachments = value
                    photoPreviews[id] = prepared.preview
                    if let draft { self.draft = try await save(draft) }
                }
                phase = draft?.takeID == nil ? .idle : .ready
            } catch { finishFailure(error) }
        }
    }


    func removePhoto(_ id: UUID) {
        guard canEditAttachments, let context = draft?.context else { return }
        phase = .loading
        operation = Task {
            do {
                try await store.removePhoto(id, context: context)
                try checkActive()
                var value = attachments
                value.photos.removeAll { $0.id == id }
                draft?.attachments = value
                photoPreviews.removeValue(forKey: id)
                if let draft { self.draft = try await save(draft) }
                phase = draft?.takeID == nil ? .idle : .ready
            } catch { finishFailure(error) }
        }
    }

    /// Only Post uploads media and hands the exact signed event to the relay queue.
    func send() async {
        guard canSend, var saved = draft, let keypair = state.keypair.to_full() else { return }
        stopPreview()
        error = nil
        phase = saved.eventJSON == nil ? .uploading : .publishing
        operation = Task {
            do {
                try checkActive()
                saved = try await save(saved)
                if saved.eventJSON == nil {
                    guard let take = saved.takeID else { throw VoiceFailure("The recording is missing.") }
                    let file = try await store.file(for: take, context: saved.context)
                    let audio = try await VoiceAudioFiles.shared.inspect(file, expectedHash: saved.sha256)
                    guard audio.size == saved.size else { throw VoiceFailure("The recording changed.") }
                    if saved.receipt == nil {
                        saved.receipt = try await uploader.upload(file: file, server: state.settings.voice_blossom_server, keypair: keypair, lifetime: state.voiceLifetime)
                        try checkActive()
                        saved = try await save(saved)
                        draft = saved
                    }
                    if var attachments = saved.attachments {
                        for index in attachments.photos.indices where attachments.photos[index].url == nil {
                            try checkActive()
                            let photo = attachments.photos[index]
                            let file = try await store.photoFile(for: photo.id, context: saved.context)
                            let url = try await photoUploader.uploadPhoto(file: file, server: state.settings.voice_blossom_server, keypair: keypair, lifetime: state.voiceLifetime)
                            try checkActive()
                            attachments.photos[index].url = url
                            saved.attachments = attachments
                            saved = try await save(saved)
                            draft = saved
                        }
                    }
                    try checkActive()
                    let snapshot = saved
                    let clientTag = state.clientTagComponents
                    let event = try await Task.detached { try VoiceEventBuilder.build(snapshot, keypair: keypair, clientTag: clientTag) }.value
                    try checkActive()
                    phase = .publishing
                    saved.eventJSON = event_to_json(ev: event)
                    saved.phase = .queued
                    saved = try await save(saved)
                    draft = saved
                }
                try checkActive()
                try await publisher.publish(saved, state: state)
                try checkActive()
                draft = await store.load(context: saved.context) ?? saved
                phase = .ready
                error = draft?.lastError
                startMonitoring()
            } catch { finishFailure(error) }
        }
        await operation?.value
    }

    /// Review local, verified bytes with the same playback owner and speeds as feed posts.
    /// Preview loading is independent of composing, so Post and discard remain responsive.
    func preview() {
        guard mode == .audio, visible, state.voiceLifetime.isActive, lease != nil, !busy,
              let saved = draft, let take = saved.takeID else { return }
        if previewLoading { stopPreview(); return }
        if VoicePlayback.shared.owner == take.uuidString { VoicePlayback.shared.toggle(); return }
        do { try VoicePlayback.shared.beginRequest(owner: take.uuidString) }
        catch { self.error = error.localizedDescription; return }
        let request = UUID()
        previewRequestID = request
        previewLoading = true
        error = nil
        previewTask = Task {
            do {
                let file = try await store.file(for: take, context: saved.context)
                let audio = try await VoiceAudioFiles.shared.inspect(file, expectedHash: saved.sha256)
                try checkActive()
                guard previewRequestID == request, draft?.id == saved.id,
                      draft?.takeID == take, mode == .audio else { throw CancellationError() }
                try VoicePlayback.shared.play(audio, owner: take.uuidString, video: state.video, from: previewPosition)
            } catch is CancellationError {}
            catch { if previewRequestID == request { self.error = error.localizedDescription } }
            if previewRequestID == request {
                previewLoading = false
                previewPosition = 0
            }
        }
    }

    /// Scrub playing audio immediately, or retain a start position while local bytes load.
    func seekPreview(_ time: TimeInterval) {
        guard time.isFinite, mode == .audio, visible, !busy, let take = draft?.takeID else { return }
        if VoicePlayback.shared.owner == take.uuidString { VoicePlayback.shared.seek(time) }
        else { previewPosition = min(max(0, time), draft?.duration ?? 0) }
    }

    /// A cancelled or hidden preview cannot take playback after another recording starts.
    func stopPreview() {
        previewRequestID = UUID()
        previewTask?.cancel()
        previewLoading = false
        previewPosition = 0
        if let owner = draft?.takeID?.uuidString,
           VoicePlayback.shared.owner == owner || VoicePlayback.shared.requestedOwner == owner {
            VoicePlayback.shared.stop()
        }
    }

    func finishAccepted() async -> Bool {
        guard !busy, draft?.phase == .accepted else { return false }
        return await beginCleanup(close: true).value
    }

    /// The explicit discard decision can cancel recognition and uploads as well as recording.
    func discard() {
        guard draft?.eventJSON == nil, !dismissalLocked else { return }
        confirmingDiscard = false
        _ = beginCleanup(close: false)
    }

    func discardAndClose() async -> Bool {
        guard !dismissalLocked else { return false }
        confirmingDiscard = false
        return await beginCleanup(close: true).value
    }

    /// Backgrounding and format changes preserve only the currently open composition.
    func suspend() {
        guard closing == nil, phase != .publishing else { return }
        stopPreview()
        VoicePlayback.shared.stop()
        // Empty preparation starts no media work. Let it settle across rapid format changes.
        if phase == .loading && draft == nil { return }
        if phase == .requestingPermission { cancelHold(); return }
        holding = false
        meter?.cancel()
        if phase == .recording { finishRecording(transcribe: false) }
        else if phase != .finalizing { operation?.cancel() }
    }

    /// Forced teardown also removes unpublished audio; a later composer always starts empty.
    func disappear() { _ = beginCleanup(close: true) }
    func waitUntilClosed() async { _ = await closing?.value }

    /// Stop owned work before deletion. Late callbacks finish before ownership is released.
    private func beginCleanup(close: Bool) -> Task<Bool, Never> {
        if close { visible = false; closingRequested = true }
        if let closing { return closing }
        let preview = previewTask
        stopPreview()
        let pending = operation
        if phase != .publishing { pending?.cancel() }
        holding = false
        meter?.cancel()
        monitor?.cancel()
        VoicePlayback.shared.stop()
        phase = .discarding
        closing = Task {
            await pending?.value
            await preview?.value
            if writerOpen {
                try? await recorder.finish()
                writerOpen = false
            }
            VoicePlayback.shared.endRecording(owner: recordingIdentity)
            do {
                if let lease {
                    let current = draft ?? VoiceDraft(context: lease.context, locale: locale)
                    try await store.discard(current, lease: lease)
                }
                photoPreviews.removeAll()
                if closingRequested {
                    if let lease { await store.release(context: lease.context, owner: lease.id) }
                    lease = nil
                    draft = nil
                    mode = .text
                } else if let context = draft?.context {
                    draft = VoiceDraft(context: context, locale: locale)
                }
                error = nil
                elapsed = 0
                phase = .idle
                closing = nil
                return true
            } catch {
                // Keep the composer and its ownership on deletion failure so the user can retry.
                self.error = "Could not discard this audio post: " + error.localizedDescription
                visible = true
                closingRequested = false
                phase = .failed
                closing = nil
                return false
            }
        }
        return closing!
    }

    private func save(_ value: VoiceDraft) async throws -> VoiceDraft {
        try checkActive()
        guard let lease else { throw CancellationError() }
        let saved = try await store.save(value, lease: lease)
        try checkActive()
        return saved
    }

    private func checkActive() throws {
        try Task.checkCancellation()
        guard state.voiceLifetime.isActive, visible, closing == nil else { throw CancellationError() }
    }

    private func finishFailure(_ failure: Error) {
        guard closing == nil, visible else { return }
        VoicePlayback.shared.endRecording(owner: recordingIdentity)
        error = failure is CancellationError ? nil : failure.localizedDescription
        phase = draft?.takeID == nil ? .idle : .failed
    }

    private func startMonitoring() {
        monitor?.cancel()
        guard visible, let context = draft?.context, draft?.eventJSON != nil else { return }
        monitor = Task {
            while !Task.isCancelled, visible, state.voiceLifetime.isActive {
                if let saved = await store.load(context: context), saved.id == draft?.id {
                    draft = saved
                    if !busy { error = saved.lastError }
                    if saved.phase == .accepted { return }
                }
                do { try await Task.sleep(nanoseconds: 1_000_000_000) }
                catch { return }
            }
        }
    }
}
