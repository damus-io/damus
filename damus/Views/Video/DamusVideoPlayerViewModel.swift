//
//  DamusVideoPlayerViewModel.swift
//  damus
//
//  Created by Bryan Montz on 9/5/23.
//

import AVFoundation
import AVKit
import Combine
import Foundation
import SwiftUI

func video_has_audio(player: AVPlayer) async -> Bool {
    do {
        let hasAudibleTracks = ((try await player.currentItem?.asset.loadMediaSelectionGroup(for: .audible)) != nil)
        let tracks = try? await player.currentItem?.asset.load(.tracks)
        let hasAudioTrack = tracks?.filter({ t in t.mediaType == .audio }).first != nil // Deal with odd cases of audio only MOV
        return hasAudibleTracks || hasAudioTrack
    } catch {
        return false
    }
}

@MainActor  // @MainActor needed because @Published properties need to be updated on the main thread.
final class DamusVideoPlayerViewModel: ObservableObject {
    private let url: URL
    private let player_item: AVPlayerItem
    let player: AVPlayer
    fileprivate let coordinator: DamusVideoCoordinator
    let player_view_controller = AVPlayerViewController()
    let id = UUID()
    
    @Published var has_audio = false
    @Published var is_live = false
    @Binding var video_size: CGSize?
    @Published var is_muted = true {
        didSet {
            if oldValue == is_muted { return }
            player.isMuted = is_muted
            coordinator.toggle_should_mute_video(url: url)
        }
    }
    @Published var is_loading = true
    @Published var current_time: TimeInterval = .zero
    @Published var is_playing = false {
        didSet {
            if oldValue == is_playing { return }
            if is_playing {
                player.play()
            }
            else {
                player.pause()
            }
        }
    }
    @Published var is_editing_current_time = false {
        didSet {
            if oldValue == is_editing_current_time { return }
            if !is_editing_current_time {
                player.seek(to: CMTime(seconds: current_time, preferredTimescale: 60))
            }
        }
    }
    var duration: TimeInterval? {
        return player.currentItem?.duration.seconds
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    private var videoSizeObserver: NSKeyValueObservation?
    private var videoDurationObserver: NSKeyValueObservation?
    private var videoCurrentTimeObserver: Any?
    private var videoIsPlayingObserver: NSKeyValueObservation?
    
    private var is_scrolled_into_view = false {
        didSet {
            if is_scrolled_into_view && !oldValue {
                // we have just scrolled from out of view into view
                coordinator.focused_video = self
            } else if !is_scrolled_into_view && oldValue {
                // we have just scrolled from in view to out of view
                if coordinator.focused_video?.id == id {
                    coordinator.focused_video = nil
                }
            }
        }
    }
    
    // MARK: - Initialization
    
    init(url: URL, video_size: Binding<CGSize?>, coordinator: DamusVideoCoordinator, mute: Bool? = nil) {
        self.url = url
        player_item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: player_item)
        self.coordinator = coordinator
        _video_size = video_size
        
        Task {
            await load()
        }
        
        is_muted = mute ?? coordinator.should_mute_video(url: url)
        player.isMuted = is_muted
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(did_play_to_end),
            name: Notification.Name.AVPlayerItemDidPlayToEndTime,
            object: player_item
        )
        
        observeVideoSize()
        observeDuration()
        observeCurrentTime()
        observeVideoIsPlaying()
    }
    
    // MARK: - Observers
    // Functions that allow us to observe certain variables and publish their changes for view updates
    
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
    
    // MARK: - Loading
    
    private func load() async {
        if let meta = coordinator.metadata(for: url) {
            has_audio = meta.has_audio
            video_size = meta.size
        } else {
            has_audio = await video_has_audio(player: player)
        }
        
        is_loading = false
    }
    
    // MARK: - Handling events
    
    func set_view_is_visible(_ is_visible: Bool) {
        is_scrolled_into_view = is_visible
    }
    
    func view_did_disappear() {
        set_view_is_visible(false)
    }
    
    @objc private func did_play_to_end() {
        player.seek(to: CMTime.zero)
        player.play()
    }
    
    // MARK: - Deinit
    
    deinit {
        videoSizeObserver?.invalidate()
        videoDurationObserver?.invalidate()
        videoIsPlayingObserver?.invalidate()
    }
    
    // MARK: - Convenience functions
    
    func play() {
        self.is_playing = true
    }
    
    func pause() {
        self.is_playing = false
    }
}

