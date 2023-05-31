//
//  VideoPlayerView.swift
//  damus
//
//  Created by William Casarin on 2023-04-05.
//

import SwiftUI

struct DamusVideoPlayer: View {
    var url: URL
    @ObservedObject var model: VideoPlayerModel
    @Binding var video_size: CGSize?
    
    var mute_icon: String {
        if model.has_audio == false || model.muted {
            return "speaker.slash"
        } else {
            return "speaker"
        }
    }
    
    var mute_icon_color: Color {
        switch self.model.has_audio {
        case .none:
            return .white
        case .some(let has_audio):
            return has_audio ? .white : .red
        }
    }
    
    var MuteIcon: some View {
        ZStack {
            Circle()
                .opacity(0.2)
                .frame(width: 32, height: 32)
                .foregroundColor(.black)
            
            Image(systemName: mute_icon)
                .padding()
                .foregroundColor(mute_icon_color)
        }
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VideoPlayer(url: url, model: model)
                .onAppear {
                    model.start()
                }
            
            if model.has_audio == true {
                MuteIcon
                    .zIndex(11.0)
                    .onTapGesture {
                        self.model.muted = !self.model.muted
                    }
            }
        }
        .onChange(of: model.size) { size in
            guard let size else {
                return
            }
            video_size = size
        }
    }
}
struct DamusVideoPlayer_Previews: PreviewProvider {
    @StateObject static var model: VideoPlayerModel = VideoPlayerModel()
    
    static var previews: some View {
        DamusVideoPlayer(url: URL(string: "http://cdn.jb55.com/s/zaps-build.mp4")!, model: model, video_size: .constant(nil))
    }
}
