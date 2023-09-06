//
//  DamusVideoPlayerViewModel.swift
//  damus
//
//  Created by Bryan Montz on 9/5/23.
//

import AVFoundation
import Combine
import Foundation
import SwiftUI

@MainActor
final class DamusVideoPlayerViewModel: ObservableObject {
    
    private let url: URL
    private let player_item: AVPlayerItem
    let player: AVPlayer
    private let controller: VideoController
    let id = UUID()
    
    @Published var has_audio = false
    @Binding var video_size: CGSize?
    @Published var is_muted = true
    @Published var is_loading = true
    
    private var cancellables = Set<AnyCancellable>()
    
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
    
    init(url: URL, video_size: Binding<CGSize?>, controller: VideoController) {
        self.url = url
        player_item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: player_item)
        self.controller = controller
        _video_size = video_size
        
        Task {
            await load()
        }
        
        is_muted = controller.should_mute_video(url: url)
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
    }
    
    private func load() async {
        if let meta = controller.metadata(for: url) {
            has_audio = meta.has_audio
            video_size = meta.size
        } else {
            has_audio = await video_has_audio(player: player)
            if let video_size = await get_video_size(player: player) {
                self.video_size = video_size
                let meta = VideoMetadata(has_audio: has_audio, size: video_size)
                controller.set_metadata(meta, url: url)
            }
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
}
