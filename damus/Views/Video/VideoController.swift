//
//  VideoController.swift
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

final class VideoController: ObservableObject {
    private var mute_states: [URL: Bool] = [:]
    private var metadatas: [URL: VideoMetadata] = [:]
    
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
    
    func size_for_url(_ url: URL) -> CGSize? {
        metadatas[url]?.size
    }
}
