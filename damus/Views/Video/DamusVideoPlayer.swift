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
        if model.muted {
            return "speaker.slash"
        } else {
            return "speaker"
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
                .foregroundColor(.white)
        }
    }
    
    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            VideoPlayer(url: url, model: model)
                .onAppear{
                    model.start()
                }
                .onDisappear {
                    model.stop()
                }
            
            MuteIcon
        }
        .onTapGesture {
            self.model.muted = !self.model.muted
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
