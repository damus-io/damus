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

@MainActor
final class DamusVideoPlayerViewModel: ObservableObject {
    
    private let url: URL
    private let maybe_cached_av_asset: VideoCache.MaybeCachedAVAsset?
    private let player_item: AVPlayerItem
    let player: AVPlayer
    fileprivate let controller: VideoController
    let player_view_controller = AVPlayerViewController()
    let id = UUID()
    
    @Published var has_audio = false
    @Published var is_live = false
    @Binding var video_size: CGSize?
    @Published var is_muted = true
    @Published var is_loading = true
    
    private var cancellables = Set<AnyCancellable>()
    
    private var videoSizeObserver: NSKeyValueObservation?
    private var videoDurationObserver: NSKeyValueObservation?
    
    private var is_scrolled_into_view = false {
        didSet {
            if is_scrolled_into_view && !oldValue {
                // we have just scrolled from out of view into view
                controller.focused_model_id = id
            } else if !is_scrolled_into_view && oldValue {
                // we have just scrolled from in view to out of view
                if controller.focused_model_id == id {
                    controller.focused_model_id = nil
                }
            }
        }
    }
    
    static func cached_video_model(url: URL, video_size: Binding<CGSize?>, controller: VideoController, mute: Bool? = nil) -> Self {
        let maybe_cached_url = (try? VideoCache.standard?.maybe_cached_url_for(video_url: url)) ?? url
        Log.info("Loading video with URL: %s",for: .render, maybe_cached_url.absoluteString)
        return Self.init(url: maybe_cached_url, video_size: video_size, controller: controller, mute: mute)
    }
    
    init(url: URL, video_size: Binding<CGSize?>, controller: VideoController, mute: Bool? = nil) {
        self.url = url
        let maybe_cached_av_asset = try? VideoCache.standard?.maybe_cached_asset_for(video_url: url)
        if maybe_cached_av_asset == nil {
            Log.info("Something went wrong when trying to load the video with the video cache. Gracefully downgrading to non-cache video loading", for: .storage)
        }
        self.maybe_cached_av_asset = maybe_cached_av_asset  // Save this wrapped asset to avoid having the loader delegate garbage collected while we still need it.
        player_item = AVPlayerItem(asset: self.maybe_cached_av_asset?.av_asset ?? AVURLAsset(url: url))
        player = AVPlayer(playerItem: player_item)
        player.automaticallyWaitsToMinimizeStalling = true
        self.controller = controller
        _video_size = video_size
        
        Task {
            await load()
        }
        
        is_muted = mute ?? controller.should_mute_video(url: url)
        player.isMuted = is_muted
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(did_play_to_end),
            name: Notification.Name.AVPlayerItemDidPlayToEndTime,
            object: player_item
        )
        
        controller.$focused_model_id
            .sink { [weak self] model_id in
                model_id == self?.id ? self?.player.play() : self?.player.pause()
            }
            .store(in: &cancellables)
        
        observeVideoSize()
        observeDuration()
    }
    
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
    
    private func load() async {
        if let meta = controller.metadata(for: url) {
            has_audio = meta.has_audio
            video_size = meta.size
        } else {
            has_audio = await video_has_audio(player: player)
        }
        
        is_loading = false
    }
    
    func did_tap_mute_button() {
        is_muted.toggle()
        player.isMuted = is_muted
        controller.toggle_should_mute_video(url: url)
    }
    
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
    
    deinit {
        videoSizeObserver?.invalidate()
        videoDurationObserver?.invalidate()
    }
}
