//
//  DamusVideoControlsView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-10-18.
//

import SwiftUI
import AVFoundation

/// A view with playback video controls, made to work seamlessly with `DamusVideoPlayer`
struct DamusVideoControlsView: View {
    @ObservedObject var video: DamusVideoPlayer
    
    var body: some View {
        VStack {
            HStack {
                Text(video_timestamp_indicator)
                    .bold()
                    .foregroundStyle(.white)
                
                Spacer()
                
                Button(action: {
                    video.is_muted.toggle()
                }, label: {
                    if video.is_muted {
                        Image(systemName: "speaker.slash")
                            .frame(width: 44, height: 44)
                    }
                    else {
                        Image(systemName: "speaker.wave.2.fill")
                            .frame(width: 44, height: 44)
                    }
                })
                .buttonStyle(PlayerCircleButtonStyle())
                .accessibilityLabel(video.is_muted ? Text("Unmute video") : Text("Mute video"))
                .accessibilityHint(Text("Toggles sound on this video"))
            }
            HStack {
                Button(action: {
                    video.is_playing.toggle()
                }, label: {
                    if video.is_playing {
                        Image(systemName: "pause.fill")
                            .frame(width: 44, height: 44)
                    }
                    else {
                        Image(systemName: "play.fill")
                            .frame(width: 44, height: 44)
                    }
                })
                .buttonStyle(PlayerCircleButtonStyle())
                .accessibilityLabel(video.is_playing ? Text("Pause video") : Text("Play video"))
                .accessibilityHint(Text("Toggles playback"))
                if let video_duration = video.duration, video_duration > 0 {
                    Slider(value: $video.current_time, in: 0...video_duration, onEditingChanged: { editing in
                        video.is_editing_current_time = editing
                    })
                    .tint(.white)
                    .accessibilityLabel(Text("Video timeline"))
                    .accessibilityValue(Text(video_timestamp_indicator))
                    .accessibilityHint(Text("Drag to scrub the video"))
                }
                else {
                    Spacer()
                }
            }
        }
        .padding(10)
    }
    
    var video_timestamp_indicator: String {
        guard let video_duration = video.duration else {
            return "\(formatTimeInterval(video.current_time))"
        }
        return "\(formatTimeInterval(video.current_time)) / \(formatTimeInterval(video_duration))"
    }
    
    func formatTimeInterval(_ interval: TimeInterval) -> String {
        if interval.isNaN {
            return "--:--"
        }
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = interval >= 60 * 60 ? [.hour, .minute, .second] : [.minute, .second]
        formatter.unitsStyle = .positional
        formatter.zeroFormattingBehavior = [.pad]

        guard let formattedString = formatter.string(from: interval) else {
            return ""
        }
        return formattedString
    }
}

struct PlayerCircleButtonStyle: ButtonStyle {
    let padding: CGFloat

    init(padding: CGFloat = 8.0) {
        self.padding = padding
    }

    func makeBody(configuration: Self.Configuration) -> some View {
        return configuration.label
            .padding(padding)
            .foregroundColor(Color.white)
            .background {
                Circle()
                    .fill(.ultraThinMaterial) // Use material for better contrast and adaptive appearance.
            }
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
    }
}
