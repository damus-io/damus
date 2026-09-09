import SwiftUI
import AVFoundation
import UIKit

/// Shared ownership prevents two voice rows (including quoted rows) playing at once.
@MainActor
final class VoicePlayback: NSObject, ObservableObject, AVAudioPlayerDelegate {
    static let shared = VoicePlayback()
    @Published private(set) var owner: String?
    @Published private(set) var requestedOwner: String?
    private var recordingOwner: UUID?
    var isRecording: Bool { recordingOwner != nil }

    /// Reserving at the user's tap prevents older downloads from taking playback later.
    func beginRequest(owner: String) throws {
        guard !isRecording else { throw VoiceFailure("Finish recording before playing audio.") }
        stop()
        requestedOwner = owner
    }

    func beginRecording(owner: UUID, video: DamusVideoCoordinator) throws {
        guard recordingOwner == nil else { throw VoiceFailure("Another recording is still active.") }
        stop()
        recordingOwner = owner
        video.focused_video?.pause()
    }

    func endRecording(owner: UUID) {
        if recordingOwner == owner { recordingOwner = nil }
    }
    @Published private(set) var isPlaying = false
    @Published private(set) var position: TimeInterval = 0
    @Published private(set) var duration: TimeInterval = 0
    /// Shared across rows for this session; stopping or changing posts keeps the chosen speed.
    @Published private(set) var playbackRate: VoicePlaybackRate = .x1
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var previousSession: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(routeChanged(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(stop), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    /// Prepared audio owns the verified bytes, including during cache eviction.
    /// `start` lets a row begin partway through, so an idle scrub is a start position.
    func play(_ audio: PreparedVoiceAudio, owner: String, video: DamusVideoCoordinator?, from start: TimeInterval = 0) throws {
        guard !isRecording, requestedOwner == owner else { throw CancellationError() }
        stop()
        requestedOwner = owner
        video?.focused_video?.pause()
        let session = AVAudioSession.sharedInstance()
        previousSession = (session.category, session.mode, session.categoryOptions)
        do {
            try session.setCategory(.playback, mode: .spokenAudio)
            try session.setActive(true)
            self.player = audio.player
            self.owner = owner
            self.duration = audio.duration
            audio.player.delegate = self
            audio.player.rate = playbackRate.playerRate
            if start > 0 { seek(start) }
            guard audio.player.play() else { throw VoiceFailure("The recording could not start playing.") }
            isPlaying = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.position = self?.player?.currentTime ?? 0 }
            }
        } catch { stop(); throw error }
    }

    /// Apply a new speed in place, without resuming paused audio or starting an idle row.
    func cyclePlaybackRate() {
        playbackRate.cycle()
        player?.rate = playbackRate.playerRate
    }

    func toggle() {
        guard let player else { return }
        if isPlaying { player.pause() } else { player.play() }
        isPlaying = player.isPlaying
    }

    func seek(_ time: TimeInterval) {
        guard time.isFinite else { return }
        player?.currentTime = min(max(0, time), duration)
        position = player?.currentTime ?? 0
    }

    /// Return the audio session to its prior category and release our active ownership.
    @objc func stop() {
        timer?.invalidate()
        timer = nil
        player?.stop()
        player = nil
        owner = nil
        requestedOwner = nil
        isPlaying = false
        position = 0
        if let previous = previousSession {
            previousSession = nil
            let session = AVAudioSession.sharedInstance()
            try? session.setActive(false, options: .notifyOthersOnDeactivation)
            try? session.setCategory(previous.0, mode: previous.1, options: previous.2)
        }
    }

    @objc private func interrupted(_ notification: Notification) {
        guard let type = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              type == AVAudioSession.InterruptionType.began.rawValue else { return }
        stop()
    }

    @objc private func routeChanged(_ notification: Notification) {
        guard let reason = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
        stop()
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.stop()
        }
    }

    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        Task { @MainActor [weak self] in
            guard let self, self.player === player else { return }
            self.stop()
        }
    }
}

/// Explicit playback only: merely displaying a post never downloads its recording.
struct VoicePlayerView: View {
    let event: NostrEvent
    let video: DamusVideoCoordinator
    /// The post's `duration` tag: the only length known before its recording is fetched.
    private let statedDuration: TimeInterval?
    @ObservedObject private var playback = VoicePlayback.shared
    @State private var loading = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var requestID = UUID()
    @State private var identity = UUID().uuidString
    /// Decoded length from the first play; outlives `stop()` so a finished row keeps its length.
    @State private var measuredDuration: TimeInterval?
    /// Where an idle scrub was released; playback starts there once the recording is ready.
    @State private var pendingSeek: TimeInterval?

    init(event: NostrEvent, video: DamusVideoCoordinator) {
        self.event = event
        self.video = video
        statedDuration = (try? VoiceMediaReference(tags: event.tags.strings()))?.statedDuration
    }

    private var owns: Bool { playback.owner == identity }
    /// The tag is advisory; the decoded file's length replaces it once heard.
    private var length: TimeInterval? { owns ? playback.duration : (measuredDuration ?? statedDuration) }
    /// Idle and loading rows show the pending start position; a playing row tracks the player.
    private var knob: TimeInterval { owns ? playback.position : (pendingSeek ?? 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Slider(value: Binding(get: { knob }, set: { scrub($0) }), in: 0...max(1, length ?? 0),
                       onEditingChanged: { editing in scrubEnded(editing) })
                    .tint(DamusColors.adaptablePurpleForeground)
                    .disabled(!owns && length == nil)
                    .accessibilityLabel("Recording position")
                    .accessibilityHint(owns ? "" : "Adjust to choose where playback starts")
                    .accessibilityIdentifier("voice.scrubber")
                speedButton
                playButton
            }
            .padding(.leading, 12)
            .padding(.trailing, 8)
            .padding(.vertical, 8)
            .background(DamusColors.adaptablePurpleBackground.opacity(0.3),
                        in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            if let error { Text(error).font(.caption).foregroundColor(.secondary).accessibilityIdentifier("voice.mediaError") }
        }
        // The parent post stack supplies the spacing below the player.
        .padding(.top, 8)
        .onDisappear {
            requestID = UUID()
            task?.cancel()
            loading = false
            pendingSeek = nil
            if owns || playback.requestedOwner == identity { playback.stop() }
        }
    }

    /// Fixed control sizes keep loading, play and pause from shifting the scrubber.
    private var playButton: some View {
        Button(action: toggle) {
            ZStack {
                Circle().fill(LINEAR_GRADIENT)
                if loading {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: owns && playback.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)
                }
            }
            .frame(width: 52, height: 52)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(loading ? "Cancel loading voice recording" :
                            (owns && playback.isPlaying ? "Pause voice recording" : "Play voice recording"))
        .accessibilityIdentifier("voice.play")
    }

    private var speedButton: some View {
        Button(action: playback.cyclePlaybackRate) {
            Text(playback.playbackRate.label)
                .font(.system(.body, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundColor(DamusColors.adaptableBlack)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Playback speed")
        .accessibilityValue(playback.playbackRate.label)
        .accessibilityHint("Cycles through three playback speeds")
        .accessibilityIdentifier("voice.speed")
    }

    /// Pause or resume while this row plays, cancel while it loads, otherwise start from the knob.
    private func toggle() {
        if owns { playback.toggle(); return }
        if loading { cancelLoad(); return }
        start()
    }

    /// The knob is a start position until this row owns playback, then a live seek.
    private func scrub(_ time: TimeInterval) {
        if owns { playback.seek(time) } else { pendingSeek = time }
    }

    /// Releasing an idle knob starts playback there; a scrub during loading waits for the recording.
    private func scrubEnded(_ editing: Bool) {
        guard !editing, !owns, !loading else { return }
        start()
    }

    private func cancelLoad() {
        requestID = UUID()
        task?.cancel()
        loading = false
        pendingSeek = nil
        if playback.requestedOwner == identity { playback.stop() }
    }

    /// Fence loading completions to this row, and verify signatures before fetching media.
    private func start() {
        do { try playback.beginRequest(owner: identity) }
        catch { self.error = error.localizedDescription; pendingSeek = nil; return }
        let request = UUID()
        requestID = request
        loading = true
        error = nil
        let note = event.to_owned()
        task = Task {
            do {
                let validation = Task.detached { () throws -> VoiceMediaReference in
                    guard note.known_kind == .voice, !note.is_rumor, note.verify() else { throw VoiceFailure("This voice post could not be verified.") }
                    return try VoiceMediaReference(tags: note.tags.strings())
                }
                let reference = try await withTaskCancellationHandler(operation: { try await validation.value }, onCancel: { validation.cancel() })
                let audio = try await VoiceAudioFiles.shared.remote(reference)
                try Task.checkCancellation()
                guard requestID == request else { return }
                try playback.play(audio, owner: identity, video: video, from: pendingSeek ?? 0)
                measuredDuration = audio.duration
            } catch is CancellationError {}
            catch { if requestID == request { self.error = error.localizedDescription } }
            if requestID == request { loading = false; pendingSeek = nil }
        }
    }
}
