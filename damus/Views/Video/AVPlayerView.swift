//
//  AVPlayerView.swift
//  damus
//
//  Created by Bryan Montz on 9/4/23.
//

import Foundation
import AVKit
import SwiftUI

struct AVPlayerView: UIViewControllerRepresentable {
    
    let player: AVPlayer
    
    func makeUIViewController(context: Context) -> AVPlayerViewController {
        AVPlayerViewController()
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
