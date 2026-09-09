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
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var previousSession: (AVAudioSession.Category, AVAudioSession.Mode, AVAudioSession.CategoryOptions)?

    override private init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(interrupted(_:)), name: AVAudioSession.interruptionNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(routeChanged(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(stop), name: UIApplication.didEnterBackgroundNotification, object: nil)
    }

    /// Prepared audio owns the verified bytes, including during cache eviction.
    func play(_ audio: PreparedVoiceAudio, owner: String, video: DamusVideoCoordinator?) throws {
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
            guard audio.player.play() else { throw VoiceFailure("The recording could not start playing.") }
            isPlaying = true
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.position = self?.player?.currentTime ?? 0 }
            }
        } catch { stop(); throw error }
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
    @ObservedObject private var playback = VoicePlayback.shared
    @State private var loading = false
    @State private var error: String?
    @State private var task: Task<Void, Never>?
    @State private var requestID = UUID()
    @State private var identity = UUID().uuidString

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: toggle) {
                    if loading { ProgressView() }
                    else { Image(systemName: playback.owner == identity && playback.isPlaying ? "pause.circle.fill" : "play.circle.fill").font(.title) }
                }
                .accessibilityLabel(playback.owner == identity && playback.isPlaying ? "Pause voice recording" : "Play voice recording")
                .accessibilityIdentifier("voice.play")
                Text("Voice post")
                if playback.owner == identity {
                    Slider(value: Binding(get: { playback.position }, set: { playback.seek($0) }), in: 0...max(1, playback.duration))
                        .accessibilityLabel("Recording position")
                    Text(Duration.seconds(playback.duration).formatted(.time(pattern: .minuteSecond)))
                        .monospacedDigit()
                }
            }
            if let error { Text(error).font(.caption).foregroundColor(.secondary).accessibilityIdentifier("voice.mediaError") }
        }
        .padding(.vertical, 8)
        .onDisappear {
            requestID = UUID()
            task?.cancel()
            loading = false
            if playback.owner == identity || playback.requestedOwner == identity { playback.stop() }
        }
    }

    /// Fence loading completions to this row, and verify signatures before fetching media.
    private func toggle() {
        if playback.owner == identity { playback.toggle(); return }
        if loading {
            requestID = UUID(); task?.cancel(); loading = false
            if playback.requestedOwner == identity { playback.stop() }
            return
        }
        do { try playback.beginRequest(owner: identity) }
        catch { self.error = error.localizedDescription; return }
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
                try playback.play(audio, owner: identity, video: video)
            } catch is CancellationError {}
            catch { if requestID == request { self.error = error.localizedDescription } }
            if requestID == request { loading = false }
        }
    }
}
