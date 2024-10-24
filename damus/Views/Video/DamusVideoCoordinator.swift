//
//  DamusVideoCoordinator.swift
//  damus
//
//  Created by Bryan Montz on 9/3/23.
//

import Combine
import Foundation

struct VideoMetadata {
    let has_audio: Bool
    let size: CGSize
}

/// DamusVideoCoordinator is responsible for coordinating the various video players in the damus app.
/// The goals of this object are to:
/// - ensure some video playing states (such as mute state) are consistent across different video player view instances of the same video
/// - ensure only one video is playing at a time
/// - Provide global video playback controls to control the currently playing video
///
/// This is used as a singleton object (one per DamusState), which gets passed around to video players, which can then interact with the coordinator to ensure an app-wide coherent experience
///
/// A good analogy here is that video players and their models/states are like individual car drivers, and this coordinator is like a traffic control person that ensures cars don't crash each other.
final class DamusVideoCoordinator: ObservableObject {
    private var mute_states: [URL: Bool] = [:]
    private var current_time_states: [URL: TimeInterval] = [:]
    private var metadatas: [URL: VideoMetadata] = [:]
    private var visible_players_stack: [DamusVideoPlayerViewModel] = []
    private var visible_high_priority_players_stack: [DamusVideoPlayerViewModel] = []
    
    /// The video currently in focus
    /// This can only be chosen by the coordinator. To get a video in focus, use one of the instance methods that provide an interface for focus control.
    @Published private(set) var focused_video: DamusVideoPlayerViewModel? {
        didSet {
            DispatchQueue.main.async { [self] in
                if oldValue?.id == focused_video?.id { return }
                oldValue?.pause()
                focused_video?.play()
                Log.info("VIDEO_COORDINATOR: %s paused, playing %s", for: .video_coordination, oldValue?.id.uuidString ?? "no video", focused_video?.id.uuidString ?? "no video")
            }
        }
    }
    
    func set_should_mute_video(url: URL, state: Bool) {
        mute_states[url] = state
        
        objectWillChange.send()
    }
    
    func should_mute_video(url: URL) -> Bool {
        mute_states[url] ?? true
    }
    
    func current_time(for url: URL) -> TimeInterval? {
        return current_time_states[url]
    }
    
    func set_current_time(for url: URL, time: TimeInterval) {
        current_time_states[url] = time
    }
    
    func set_metadata(_ metadata: VideoMetadata, url: URL) {
        metadatas[url] = metadata
    }
    
    func metadata(for url: URL) -> VideoMetadata? {
        metadatas[url]
    }
    
    func size_for_url(_ url: URL) -> CGSize? {
        metadatas[url]?.size
    }
    
    // MARK: - Interface for video players to come to the foreground
    // This portion provides an interface for video players to signal their visibility changes,
    // and implements some coordination logic to choose which video to play and pause at a given time.
    
    func register_visible_player(_ player: DamusVideoPlayerViewModel) {
        Log.info("VIDEO_COORDINATOR: %s marked visible", for: .video_coordination, player.id.uuidString)
        switch player.focus_context {
            case .scroll_view_item:
                if visible_players_stack.first(where: { $0.id == player.id }) != nil { return } // Entry exists already
                visible_players_stack.append(player)
            case .full_screen:
                if visible_high_priority_players_stack.first(where: { $0.id == player.id }) != nil { return } // Entry exists already
                visible_high_priority_players_stack.append(player)
        }
        self.select_focused_video()
    }
    
    func register_player_is_out_of_view(_ player: DamusVideoPlayerViewModel) {
        Log.info("VIDEO_COORDINATOR: %s marked hidden", for: .video_coordination, player.id.uuidString)
        visible_players_stack.removeAll(where: { $0.id == player.id })
        visible_high_priority_players_stack.removeAll(where: { $0.id == player.id })
        self.select_focused_video()
    }
    
    private func select_focused_video() {
        // The focused video will always be the last one that was inserted — similar to a LIFO stack
        // The reason is that:
        // - both a LIFO stack and a FIFO queue are decent at selecting videos when scrolling on the Y axis (timeline),
        // - The LIFO stack is better at selecting videos when navigating on the Z axis (e.g. opening and closing full screen covers or sheets), since those sheets operate like a stack as well
        //
        // Also, always prefer to play a high priority item, falling back to regular ones when necessary
        focused_video = visible_high_priority_players_stack.last ?? visible_players_stack.last
        Log.info("VIDEO_COORDINATOR: high priority stack: %s", for: .video_coordination, visible_high_priority_players_stack.map({ $0.id.uuidString }).debugDescription)
        Log.info("VIDEO_COORDINATOR: stack: %s", for: .video_coordination, visible_players_stack.map({ $0.id.uuidString }).debugDescription)
    }
}
