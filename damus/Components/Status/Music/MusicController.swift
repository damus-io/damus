//
//  MusicController.swift
//  damus
//
//  Created by William Casarin on 2023-08-21.
//
import SwiftUI
import MediaPlayer

enum MusicState {
    case playback_state(MPMusicPlaybackState)
    case song(MPMediaItem?)
}

class MusicController {
    let player: MPMusicPlayerController

    let onChange: (MusicState) -> ()

    init(onChange: @escaping (MusicState) -> ()) {
        player = .systemMusicPlayer

        player.beginGeneratingPlaybackNotifications()

        self.onChange = onChange

        print("Playback State: \(player.playbackState)")
        print("Now Playing Item: \(player.nowPlayingItem?.title ?? "None")")

        NotificationCenter.default.addObserver(self, selector: #selector(self.songChanged(notification:)), name: .MPMusicPlayerControllerNowPlayingItemDidChange, object: player)

        NotificationCenter.default.addObserver(self, selector: #selector(self.playbackStatusChanged(notification:)), name: .MPMusicPlayerControllerPlaybackStateDidChange, object: player)
    }

    deinit {
        print("deinit musiccontroller")
    }

    @objc
    func songChanged(notification: Notification) {
        onChange(.song(player.nowPlayingItem))
    }

    @objc
    func playbackStatusChanged(notification: Notification) {
        onChange(.playback_state(player.playbackState))
    }
}
