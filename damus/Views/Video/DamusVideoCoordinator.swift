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
    private var metadatas: [URL: VideoMetadata] = [:]
    
    // MARK: Coordinator state
    // Members representing the state of the coordinator itself
    
    private var full_screen_mode: Bool = false {
        didSet {
        }
    }
    
    @Published var focused_model_id: UUID?
    
    func toggle_should_mute_video(url: URL) {
        let state = mute_states[url] ?? true
        mute_states[url] = !state
        
        objectWillChange.send()
    }
    
    func should_mute_video(url: URL) -> Bool {
        mute_states[url] ?? true
    }
    
    func set_metadata(_ metadata: VideoMetadata, url: URL) {
        metadatas[url] = metadata
    }
    
    func metadata(for url: URL) -> VideoMetadata? {
        metadatas[url]
    }
     
    // MARK: - Additional interface to help with video coordination
    
    func set_full_screen_mode(_ is_full_screen: Bool) {
        full_screen_mode = is_full_screen
    }
    
    func size_for_url(_ url: URL) -> CGSize? {
        metadatas[url]?.size
    }
}
