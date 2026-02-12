//
//  DamusVideoPlayer.swift
//  damus
//
//  Created by Bryan Montz on 9/5/23.
//

import AVFoundation
import AVKit
import Combine
import Foundation
import SwiftUI

#if KSPLAYER_ENABLED
import KSPlayer
#endif

#if KSPLAYER_ENABLED
/// Protocol for creating fallback players, enabling test injection.
protocol FallbackPlayerFactory {
    func makeFallbackPlayer(url: URL, options: KSOptions) -> any MediaPlayerProtocol
}

/// Default production factory.
struct DefaultFallbackPlayerFactory: FallbackPlayerFactory {
    func makeFallbackPlayer(url: URL, options: KSOptions) -> any MediaPlayerProtocol {
        return KSMEPlayer(url: url, options: options)
    }
}
#endif

/// DamusVideoPlayer has the function of wrapping `AVPlayer` and exposing a control interface that integrates seamlessly with SwiftUI views
///
/// This is **NOT** a video player view. This is a headless video object concerned about the video and its playback. To display a video, you need `DamusVideoPlayerView`
/// This is also **NOT** a control view. Please see `DamusVideoControlsView` for that.
///
/// **Implementation notes:**
/// - `@MainActor` is needed because `@Published` properties need to be updated on the main thread to avoid SwiftUI mutations within a single render pass
/// - `@Published` variables are the chosen interface because they integrate very seamlessly with SwiftUI views. Avoid the use of procedural functions to avoid SwiftUI state desync.
@MainActor final class DamusVideoPlayer: ObservableObject {

    // MARK: Immutable foundational instance members

    /// The URL of the video
    let url: URL


    // MARK: Internal state

    /// The underlying AVPlayer that we are wrapping.
    /// This is not public because we don't want any callers of this class controlling the `AVPlayer` directly, we want them to go through our interface
    /// This measure helps avoid state inconsistencies and other flakiness. DO NOT USE THIS OUTSIDE `DamusVideoPlayer`
    private var player: AVPlayer


    // MARK: SwiftUI-friendly interface

    /// Indicates whether the video has audio at all
    @Published private(set) var has_audio = false
    /// Whether whether this is a live video
    @Published private(set) var is_live = false
    /// The video size
    @Published private(set) var video_size: CGSize?
    /// Whether or not to mute the video
    @Published var is_muted = true {
        didSet {
            if oldValue == is_muted { return }
            #if KSPLAYER_ENABLED
            if is_using_fallback {
                fallbackPlayer?.isMuted = is_muted
                return
            }
            #endif
            player.isMuted = is_muted
        }
    }
    /// Whether the video is loading
    @Published private(set) var is_loading = true
    /// The current time of playback, in seconds
    /// Usage note: If editing (such as in a slider), make sure to set `is_editing_current_time` to `true` to detach this value from the current playback
    @Published var current_time: TimeInterval = .zero
    /// Whether video is playing or not
    @Published var is_playing = false {
        didSet {
            if oldValue == is_playing { return }
            // When scrubbing, the playback control is temporarily decoupled, so don't play/pause our player
            // When scrubbing stops, the `is_editing_current_time` handler will automatically play/pause depending on `is_playing`
            if is_editing_current_time { return }
            #if KSPLAYER_ENABLED
            if is_using_fallback {
                if is_playing { fallbackPlayer?.play() }
                else { fallbackPlayer?.pause() }
                return
            }
            #endif
            if is_playing {
                player.play()
            }
            else {
                player.pause()
            }
        }
    }
    /// Whether the current time is being manually edited (e.g. when user is scrubbing through the video)
    /// **Implementation note:** When set to `true`, this decouples the `current_time` from the video playback observer — in a way analogous to a clutch on a standard transmission car, if you are into Automotive engineering.
    @Published var is_editing_current_time = false {
        didSet {
            if oldValue == is_editing_current_time { return }

            // Scrubbing started — pause playback while user drags
            if is_editing_current_time {
                #if KSPLAYER_ENABLED
                if is_using_fallback {
                    fallbackPlayer?.pause()
                    return
                }
                #endif
                if self.is_playing { self.player.pause() }
                return
            }

            // Scrubbing ended — seek to new position and resume if was playing
            #if KSPLAYER_ENABLED
            if is_using_fallback {
                fallbackPlayer?.seek(time: current_time, completion: { [weak self] finished in
                    guard let self, finished else { return }
                    DispatchQueue.main.async { [weak self] in
                        guard let self else { return }
                        if self.is_playing { self.fallbackPlayer?.play() }
                    }
                })
                return
            }
            #endif
            Task {
                await self.player.seek(to: CMTime(seconds: current_time, preferredTimescale: 60))
                if self.is_playing {
                    self.player.play()
                }
            }
        }
    }
    /// The duration of the video, in seconds.
    var duration: TimeInterval? {
        #if KSPLAYER_ENABLED
        if is_using_fallback { return fallbackPlayer?.duration }
        #endif
        return player.currentItem?.duration.seconds
    }

    /// Whether we're using the KSMEPlayer fallback (for unsupported codecs like VP9)
    @Published private(set) var is_using_fallback = false

    #if KSPLAYER_ENABLED
    /// Factory for creating fallback players — defaults to KSMEPlayer, tests inject stubs.
    private let fallbackFactory: any FallbackPlayerFactory
    /// The fallback player, created only on MainActor when AVPlayer fails.
    /// Typed as `any MediaPlayerProtocol` (not `KSMEPlayer`) so tests can inject stubs.
    private(set) var fallbackPlayer: (any MediaPlayerProtocol)?
    /// Stable container view — KSMEPlayer may swap its internal view during operation
    private(set) var fallbackContainerView: UIView?
    /// Timer for polling fallback player's currentPlaybackTime
    private var fallbackTimeTimer: Timer?
    /// Track whether prepareToPlay has been called on the fallback player.
    private var fallbackPrepared = false
    /// Set when fallback player hits a terminal error — prevents delegate callbacks from re-setting is_loading
    private var fallbackFailed = false
    #endif

    // MARK: Internal instance members

    private var cancellables = Set<AnyCancellable>()
    private var videoSizeObserver: NSKeyValueObservation?
    private var videoDurationObserver: NSKeyValueObservation?
    private var videoCurrentTimeObserver: Any?
    private var videoIsPlayingObserver: NSKeyValueObservation?
    private var playerItemStatusObserver: NSKeyValueObservation?


    // MARK: - Initialization, deinitialization and reinitialization

    #if KSPLAYER_ENABLED
    public init(url: URL, fallbackFactory: any FallbackPlayerFactory = DefaultFallbackPlayerFactory()) {
        self.fallbackFactory = fallbackFactory
        self.url = url
        // Initialize with an empty player first
        self.player = AVPlayer()
        self.video_size = nil

        // Creating the player item is an expensive action. Create it on a background thread to avoid performance issues.
        Task.detached(priority: TaskPriority.userInitiated) {
            self.loadPlayerItem(url: url)
        }
    }
    #else
    public init(url: URL) {
        self.url = url
        // Initialize with an empty player first
        self.player = AVPlayer()
        self.video_size = nil

        // Creating the player item is an expensive action. Create it on a background thread to avoid performance issues.
        Task.detached(priority: TaskPriority.userInitiated) {
            self.loadPlayerItem(url: url)
        }
    }
    #endif

    nonisolated private func loadPlayerItem(url: URL) {
        let playerItem = AVPlayerItem(url: url)

        DispatchQueue.main.async {
            self.player.replaceCurrentItem(with: playerItem)
            self.observePlayerItemStatus()
            Task { await self.load() }
        }
    }

    func reinitializePlayer() {
        Log.info("[debug-video] DamusVideoPlayer: Reinitializing internal player…", for: .video_coordination)

        // Tear down
        tearDownObservers()

        #if KSPLAYER_ENABLED
        if is_using_fallback {
            fallbackTimeTimer?.invalidate()
            fallbackPlayer?.shutdown()
            fallbackPlayer = nil
            fallbackContainerView = nil
            is_using_fallback = false
            fallbackPrepared = false
            fallbackFailed = false
        }
        #endif

        // Initialize player with nil item first
        self.player.replaceCurrentItem(with: nil)

        // Creating the player item is an expensive action. Create it on a background thread to avoid performance issues.
        Task.detached(priority: TaskPriority.userInitiated) {
            self.loadPlayerItem(url: self.url)
        }
    }

    /// Internally loads this class
    private func load() async {
        Task {
            has_audio = await self.video_has_audio()
            is_loading = false
        }

        player.isMuted = is_muted

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(did_play_to_end),
            name: Notification.Name.AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )

        // Observe runtime decode failures (status can reach .readyToPlay but decode fails later)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(playerItemFailedToPlayToEnd(_:)),
            name: .AVPlayerItemFailedToPlayToEndTime,
            object: player.currentItem
        )

        observeVideoSize()
        observeDuration()
        observeCurrentTime()
        observeVideoIsPlaying()
    }

    deinit {
        // Inline cleanup — deinit is nonisolated, can't call @MainActor methods.
        videoSizeObserver?.invalidate()
        videoDurationObserver?.invalidate()
        videoIsPlayingObserver?.invalidate()
        playerItemStatusObserver?.invalidate()
        if let observer = videoCurrentTimeObserver {
            player.removeTimeObserver(observer)
        }
        NotificationCenter.default.removeObserver(self)
        #if KSPLAYER_ENABLED
        fallbackTimeTimer?.invalidate()
        fallbackPlayer?.shutdown()
        #endif
    }

    /// Unified teardown of all AVPlayer observers.
    /// Called from fallback activation, reinitialize, and before setting up new observers.
    private func tearDownObservers() {
        videoSizeObserver?.invalidate()
        videoSizeObserver = nil
        videoDurationObserver?.invalidate()
        videoDurationObserver = nil
        videoIsPlayingObserver?.invalidate()
        videoIsPlayingObserver = nil
        playerItemStatusObserver?.invalidate()
        playerItemStatusObserver = nil
        if let observer = videoCurrentTimeObserver {
            player.removeTimeObserver(observer)
            videoCurrentTimeObserver = nil
        }
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemDidPlayToEndTime, object: nil)
        NotificationCenter.default.removeObserver(self, name: .AVPlayerItemFailedToPlayToEndTime, object: nil)
    }

    // MARK: - Observers
    // Functions that allow us to observe certain variables and publish their changes for view updates
    // These are all private because they are part of the internal logic

    private func observeVideoSize() {
        videoSizeObserver = player.currentItem?.observe(\.presentationSize, options: [.new], changeHandler: { [weak self] (playerItem, change) in
            guard let self else { return }
            if let newSize = change.newValue, newSize != .zero {
                DispatchQueue.main.async {
                    self.video_size = newSize  // Update the bound value
                }
            }
        })
    }

    private func observeDuration() {
        videoDurationObserver = player.currentItem?.observe(\.duration, options: [.new], changeHandler: { [weak self] (playerItem, change) in
            guard let self else { return }
            if let newDuration = change.newValue, newDuration != .zero {
                DispatchQueue.main.async {
                    self.is_live = newDuration == .indefinite
                }
            }
        })
    }

    private func observeCurrentTime() {
        videoCurrentTimeObserver = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { [weak self] time in
            guard let self else { return }
            DispatchQueue.main.async {  // Must use main thread to update @Published properties
                if self.is_editing_current_time == false {
                    self.current_time = time.seconds
                }
            }
        }
    }

    private func observeVideoIsPlaying() {
        videoIsPlayingObserver = player.observe(\.rate, changeHandler: { [weak self] (player, change) in
            guard let self else { return }
            guard let new_rate = change.newValue else { return }
            DispatchQueue.main.async {
                self.is_playing = new_rate > 0
            }
        })
    }

    /// Observes AVPlayerItem.status via KVO to detect playback failures and trigger fallback.
    private func observePlayerItemStatus() {
        playerItemStatusObserver = player.currentItem?.observe(\.status) { [weak self] item, _ in
            guard let self else { return }
            DispatchQueue.main.async {
                switch item.status {
                case .failed:
                    let nsErr = item.error as NSError?
                    Log.info("[debug-video] DamusVideoPlayer: AVPlayerItem status → .failed (domain=%s code=%d desc='%s')",
                             for: .video_coordination,
                             nsErr?.domain ?? "nil", nsErr?.code ?? 0,
                             nsErr?.localizedDescription ?? "nil")
                    self.handleAVPlayerFailure(error: item.error)
                case .readyToPlay:
                    Log.info("[debug-video] DamusVideoPlayer: AVPlayerItem status → .readyToPlay", for: .video_coordination)
                    break
                case .unknown:
                    break
                @unknown default:
                    break
                }
            }
        }
    }

    /// Handles AVPlayerItemFailedToPlayToEndTime notification for runtime decode failures.
    /// Dispatches to main thread since NotificationCenter may deliver on an arbitrary queue.
    @objc private func playerItemFailedToPlayToEnd(_ notification: Notification) {
        let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            let nsErr = error as NSError?
            Log.info("[debug-video] DamusVideoPlayer: AVPlayerItemFailedToPlayToEndTime (domain=%s code=%d desc='%s')",
                     for: .video_coordination,
                     nsErr?.domain ?? "nil", nsErr?.code ?? 0,
                     nsErr?.localizedDescription ?? "nil")
            self.handleAVPlayerFailure(error: error)
        }
    }

    // MARK: - AVPlayer failure handling and fallback

    /// Returns true if the error likely indicates a decode or format issue (fallback appropriate).
    /// Blocklists known non-decode AVFoundation errors; defaults to fallback for unknown AVF errors.
    ///
    /// IMPORTANT: Underlying error is checked FIRST. AVFoundation frequently wraps transport/auth
    /// errors (NSURLErrorDomain, etc.) inside AVFoundationErrorDomain. If we checked the outer
    /// AVFoundation domain first and defaulted to true, wrapped network errors would incorrectly
    /// trigger fallback. Root-cause-first ordering prevents this.
    func isLikelyDecodeError(_ error: Error?) -> Bool {
        guard let nsError = error as NSError? else {
            Log.info("[debug-video] DamusVideoPlayer: isLikelyDecodeError — nil error, assuming decode", for: .video_coordination)
            return true
        }

        Log.info("[debug-video] DamusVideoPlayer: isLikelyDecodeError — domain=%s code=%d desc='%s'",
                 for: .video_coordination, nsError.domain, nsError.code, nsError.localizedDescription)

        // Check underlying error FIRST — root cause takes priority over wrapper domain
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            Log.info("[debug-video] DamusVideoPlayer: isLikelyDecodeError — has underlying error, recursing", for: .video_coordination)
            return isLikelyDecodeError(underlying)
        }

        // Network/transport → never fallback
        if nsError.domain == NSURLErrorDomain { return false }

        // AVFoundation: blocklist known non-decode errors, default to fallback
        if nsError.domain == AVFoundationErrorDomain {
            let nonDecodeCodes: Set<Int> = [
                AVError.serverIncorrectlyConfigured.rawValue,
                AVError.contentIsProtected.rawValue,
                AVError.contentIsNotAuthorized.rawValue,
                AVError.noLongerPlayable.rawValue,
            ]
            if nonDecodeCodes.contains(nsError.code) { return false }
            // Unknown AVFoundation error with no underlying → assume decode
            return true
        }

        // Media stack internal domains: only treat as decode if this is a leaf error
        // (no underlying to recurse into). These domains contain non-decode errors too
        // (e.g. file I/O, permission), so we only assume decode when there's nothing
        // more specific to inspect.
        if nsError.domain == "CoreMediaErrorDomain" || nsError.domain == NSOSStatusErrorDomain {
            // Already checked underlying above — if we're here, there's none.
            // Log the code to help diagnose unexpected fallback triggers.
            Log.info("[debug-video] DamusVideoPlayer: media-stack error (domain=%s code=%d) with no underlying — assuming decode",
                     for: .video_coordination, nsError.domain, nsError.code)
            return true
        }

        // Unknown non-media domain with no underlying → conservatively don't fallback
        return false
    }

    /// Single entry point for all AVPlayer failure handling. Takes the error directly
    /// from the failure source (KVO or notification) to avoid re-reading stale state.
    private func handleAVPlayerFailure(error: Error?) {
        guard !is_using_fallback else { return }
        guard isLikelyDecodeError(error) else {
            Log.error("[debug-video] DamusVideoPlayer: AVPlayer failed with non-decode error: '%s'",
                      for: .video_coordination, (error as NSError?)?.localizedDescription ?? "unknown")
            is_loading = false
            is_playing = false
            return
        }
        #if KSPLAYER_ENABLED
        activateFallbackPlayer()
        #else
        Log.error("[debug-video] DamusVideoPlayer: AVPlayer failed and no fallback available", for: .video_coordination)
        is_loading = false
        is_playing = false
        #endif
    }

    #if KSPLAYER_ENABLED
    /// Activates KSMEPlayer as fallback when AVPlayer cannot decode the video.
    private func activateFallbackPlayer() {
        guard !is_using_fallback else { return }
        Log.info("[debug-video] DamusVideoPlayer: AVPlayer failed for '%s', activating KSMEPlayer fallback",
                 for: .video_coordination, url.absoluteString)

        // Tear down AVPlayer
        tearDownObservers()
        player.replaceCurrentItem(with: nil)

        // Configure KSOptions
        let options = KSOptions()
        options.isLoopPlay = true

        // Create via factory (enables test injection)
        let fallback = fallbackFactory.makeFallbackPlayer(url: self.url, options: options)
        fallback.delegate = self
        fallback.isMuted = self.is_muted

        // Stable container — KSMEPlayer.view can be swapped during fallback transitions
        let container = UIView()
        if let playerView = fallback.view {
            container.addSubview(playerView)
            playerView.translatesAutoresizingMaskIntoConstraints = false
            NSLayoutConstraint.activate([
                playerView.topAnchor.constraint(equalTo: container.topAnchor),
                playerView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                playerView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                playerView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
        }

        self.fallbackPlayer = fallback
        self.fallbackContainerView = container
        self.is_using_fallback = true
        self.fallbackPrepared = false
        self.fallbackFailed = false
        self.is_loading = true

        // Post-init: restore Damus audio session (KSMEPlayer overwrites it)
        DamusAudioSession.restore()

        // Start time polling (MediaPlayerDelegate has no periodic time callback)
        startFallbackTimePolling()

        // Always call prepareToPlay — it opens media streams.
        // play() alone only flips state.
        fallback.prepareToPlay()
        self.fallbackPrepared = true

        // If we were playing when AVPlayer failed, start the fallback player.
        // Call fallbackPlayer?.play() directly here (not via is_playing didSet)
        // because is_playing is already true — didSet won't fire (oldValue == newValue guard).
        if self.is_playing {
            fallback.play()
        }
    }

    /// Polls fallbackPlayer.currentPlaybackTime since MediaPlayerDelegate
    /// has no periodic time callback.
    ///
    /// IMPORTANT: This timer must NOT write to `is_playing`. The `is_playing`
    /// didSet routes to fallbackPlayer.play()/pause(), so mirroring playbackState
    /// back into is_playing would create a feedback loop.
    private func startFallbackTimePolling() {
        fallbackTimeTimer?.invalidate()
        fallbackTimeTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self, self.is_using_fallback else { return }
            if !self.is_editing_current_time {
                self.current_time = self.fallbackPlayer?.currentPlaybackTime ?? 0
            }
        }
    }
    #endif

    // MARK: - Other internal logic functions

    private func video_has_audio() async -> Bool {
        do {
            let hasAudibleTracks = ((try await player.currentItem?.asset.loadMediaSelectionGroup(for: .audible)) != nil)
            let tracks = try? await player.currentItem?.asset.load(.tracks)
            let hasAudioTrack = tracks?.filter({ t in t.mediaType == .audio }).first != nil // Deal with odd cases of audio only MOV
            return hasAudibleTracks || hasAudioTrack
        } catch {
            return false
        }
    }

    @objc private func did_play_to_end() {
        player.seek(to: CMTime.zero)
        player.play()
    }

    // MARK: - Convenience interface functions

    func play() {
        #if KSPLAYER_ENABLED
        if is_using_fallback {
            if !fallbackPrepared {
                fallbackPlayer?.prepareToPlay()
                fallbackPrepared = true
            }
            self.is_playing = true
            return
        }
        #endif
        switch self.player.status {
        case .failed:
            Log.error("[debug-video] DamusVideoPlayer: Failed to play video. Error: '%s'", for: .video_coordination, self.player.error?.localizedDescription ?? "no error")
            self.reinitializePlayer()
        default:
            break
        }
        self.is_playing = true
    }

    func pause() {
        self.is_playing = false
    }
}

// MARK: - KSPlayer MediaPlayerDelegate

#if KSPLAYER_ENABLED
extension DamusVideoPlayer: MediaPlayerDelegate {
    func readyToPlay(player: some MediaPlayerProtocol) {
        let size = player.naturalSize
        let duration = player.duration
        let hasAudio = !player.tracks(mediaType: .audio).isEmpty
        Log.info("[debug-video] DamusVideoPlayer: Fallback readyToPlay (size=%@, duration=%.1f)",
                 for: .video_coordination, NSCoder.string(for: size), duration)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.is_loading = false
            self.video_size = size
            self.has_audio = hasAudio
        }
    }

    func changeLoadState(player: some MediaPlayerProtocol) {
        let loadState = player.loadState
        Log.info("[debug-video] DamusVideoPlayer: Fallback loadState → %@ (fallbackFailed=%d)",
                 for: .video_coordination, "\(loadState)", fallbackFailed ? 1 : 0)
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.fallbackFailed else { return }
            switch loadState {
            case .idle, .loading:
                self.is_loading = true
            case .playable:
                self.is_loading = false
            }
        }
    }

    func changeBuffering(player: some MediaPlayerProtocol, progress: Int) {
        Log.info("[debug-video] DamusVideoPlayer: Fallback buffering %d%%", for: .video_coordination, progress)
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.fallbackFailed else { return }
            self.is_loading = progress < 100
        }
    }

    func playBack(player: some MediaPlayerProtocol, loopCount: Int) {
        Log.info("[debug-video] DamusVideoPlayer: Fallback loop count %d", for: .video_coordination, loopCount)
    }

    func finish(player: some MediaPlayerProtocol, error: Error?) {
        guard let error else {
            Log.info("[debug-video] DamusVideoPlayer: Fallback finished (no error, likely loop)", for: .video_coordination)
            return
        }
        Log.error("[debug-video] DamusVideoPlayer: Fallback player error: '%s'", for: .video_coordination, error.localizedDescription)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.fallbackFailed = true
            self.fallbackTimeTimer?.invalidate()
            self.fallbackTimeTimer = nil
            self.is_loading = false
            self.is_playing = false
        }
    }
}
#endif

// MARK: - BaseView

extension DamusVideoPlayer {
    /// The simplest view for a `DamusVideoPlayer` object.
    ///
    /// Other views with more features should use this as a base.
    ///
    /// ## Implementation notes:
    ///
    /// 1. This is defined inside `DamusVideoPlayer` to allow it to access the private `AVPlayer` instance required to initialize it, which is otherwise hidden away from every other class.
    /// 2. DO NOT write any `AVPlayer` control/manipulation code, the `AVPlayer` instance is owned by `DamusVideoPlayer` and only managed there to keep things sane.
    struct BaseView: UIViewControllerRepresentable {

        let player: DamusVideoPlayer
        let show_playback_controls: Bool

        func makeUIViewController(context: Context) -> UIViewController {
            #if KSPLAYER_ENABLED
            if player.is_using_fallback {
                let vc = UIViewController()
                if let container = player.fallbackContainerView {
                    vc.view.addSubview(container)
                    container.frame = vc.view.bounds
                    container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                }
                return vc
            }
            #endif
            let controller = AVPlayerViewController()
            controller.showsPlaybackControls = show_playback_controls
            return controller
        }

        func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
            #if KSPLAYER_ENABLED
            if player.is_using_fallback {
                guard let container = player.fallbackContainerView else { return }
                if container.superview != uiViewController.view {
                    uiViewController.view.subviews.forEach { $0.removeFromSuperview() }
                    uiViewController.view.addSubview(container)
                    container.frame = uiViewController.view.bounds
                    container.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                }
                return
            }
            #endif
            if let avController = uiViewController as? AVPlayerViewController {
                avController.player = player.player
            }
        }

        static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: ()) {
            if let avController = uiViewController as? AVPlayerViewController {
                avController.player = nil
            }
        }
    }
}
