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
            // When scrubbing, the playback control is temporarily decoupled, so don't play/pause our `AVPlayer`
            // When scrubbing stops, the `is_editing_current_time` handler will automatically play/pause depending on `is_playing`
            if is_editing_current_time { return }
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
            if !is_editing_current_time {
                Task {
                    await self.player.seek(to: CMTime(seconds: current_time, preferredTimescale: 60))
                    // Start playing video again, if we were playing before scrubbing
                    if self.is_playing {
                        self.player.play()
                    }
                }
            }
            else {
                // Pause playing video, if we were playing before we started scrubbing
                if self.is_playing { self.player.pause() }
            }
        }
    }
    /// The duration of the video, in seconds.
    var duration: TimeInterval? {
        return player.currentItem?.duration.seconds
    }
    
    // MARK: Internal instance members
    
    private var cancellables = Set<AnyCancellable>()
    private var videoSizeObserver: NSKeyValueObservation?
    private var videoDurationObserver: NSKeyValueObservation?
    private var videoCurrentTimeObserver: Any?
    private var videoIsPlayingObserver: NSKeyValueObservation?
    private var videoStatusObserver: NSKeyValueObservation?
    /// Tracks whether we've performed the initial seek to zero for this player item.
    /// Reset to `false` when the player is reinitialized (e.g., after an error recovery).
    /// This prevents redundant seeks while ensuring new player items always start at 0:00.
    private var hasPerformedInitialSeek: Bool = false
    
    
    // MARK: - Initialization, deinitialization and reinitialization
    
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
    
    nonisolated private func loadPlayerItem(url: URL) {
        let playerItem = AVPlayerItem(url: url)
        
        DispatchQueue.main.async {
            self.player.replaceCurrentItem(with: playerItem)
            Task { await self.load() }
        }
    }
    
    func reinitializePlayer() {
        Log.info("DamusVideoPlayer: Reinitializing internal player…", for: .video_coordination)

        // Tear down
        videoSizeObserver?.invalidate()
        videoDurationObserver?.invalidate()
        videoIsPlayingObserver?.invalidate()
        videoStatusObserver?.invalidate()
        hasPerformedInitialSeek = false

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
        
        observeVideoSize()
        observeDuration()
        observeCurrentTime()
        observeVideoIsPlaying()
        observePlayerItemStatus()
    }
    
    deinit {
        // These cannot be moved into their own functions due to contraints on structured concurrency
        videoSizeObserver?.invalidate()
        videoDurationObserver?.invalidate()
        videoIsPlayingObserver?.invalidate()
        videoStatusObserver?.invalidate()
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

    /// Observes the player item's status and seeks to the beginning when ready.
    ///
    /// ## Why this is needed
    /// AVPlayer does not guarantee playback starts at exactly 0:00. When loading a video,
    /// the initial position depends on keyframe alignment, codec buffering, and metadata.
    /// Short videos are especially affected as the offset becomes a noticeable portion
    /// of total duration.
    ///
    /// ## Solution
    /// We observe `AVPlayerItem.status` and perform a precise seek to `CMTime.zero` with
    /// zero tolerance once the item reports `.readyToPlay`. This ensures the first frame
    /// is always shown, regardless of the video's internal structure.
    ///
    /// - SeeAlso: https://github.com/damus-io/damus/issues/3100
    private func observePlayerItemStatus() {
        videoStatusObserver = player.currentItem?.observe(\.status, options: [.new]) { [weak self] (playerItem, change) in
            guard let self else { return }
            guard playerItem.status == .readyToPlay else { return }

            DispatchQueue.main.async {
                guard !self.hasPerformedInitialSeek else { return }
                self.hasPerformedInitialSeek = true
                // toleranceBefore/After: .zero ensures frame-accurate seek to the exact start
                self.player.seek(to: CMTime.zero, toleranceBefore: .zero, toleranceAfter: .zero)
            }
        }
    }
    
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
        switch self.player.status {
        case .failed:
            Log.error("DamusVideoPlayer: Failed to play video. Error: '%s'", for: .video_coordination, self.player.error?.localizedDescription ?? "no error")
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
        
        func makeUIViewController(context: Context) -> AVPlayerViewController {
            let controller = AVPlayerViewController()
            controller.showsPlaybackControls = show_playback_controls
            return controller
        }
        
        func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
            /// - If `player.player` is changed (e.g. `DamusVideoPlayer` gets reinitialized), this will refresh the video player to the new working one.
            /// - If `player.player` is unchanged, this is basically a very low cost no-op (Because `AVPlayer` is a class type, this assignment only copies a pointer, not a large structure)
            uiViewController.player = player.player
        }
        
        static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: ()) {
            uiViewController.player = nil
        }
    }
}
