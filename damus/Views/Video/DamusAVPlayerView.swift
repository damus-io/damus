//
//  AVPlayerView.swift
//  damus
//
//  Created by Bryan Montz on 9/4/23.
//

import Foundation
import AVKit
import SwiftUI

struct DamusAVPlayerView: UIViewControllerRepresentable {
    
    let player: AVPlayer
    var controller: AVPlayerViewController
    let show_playback_controls: Bool
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        self.controller.showsPlaybackControls = show_playback_controls
        return self.controller
    }
    
    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        if uiViewController.player == nil {
            uiViewController.player = player
            player.play()
        }
    }
    
    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: ()) {
        uiViewController.player?.pause()
        uiViewController.player = nil
    }
}
