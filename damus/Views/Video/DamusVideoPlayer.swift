//
//  VideoPlayerView.swift
//  damus
//
//  Created by William Casarin on 2023-04-05.
//

import SwiftUI

/// get coordinates in Global reference frame given a Local point & geometry
func globalCoordinate(localX x: CGFloat, localY y: CGFloat,
                      localGeometry geo: GeometryProxy) -> CGPoint {
    let localPoint = CGPoint(x: x, y: y)
    return geo.frame(in: .global).origin.applying(
        .init(translationX: localPoint.x, y: localPoint.y)
    )
}

struct DamusVideoPlayer: View {
    let url: URL
    @StateObject var model: DamusVideoPlayerViewModel
    @EnvironmentObject private var orientationTracker: OrientationTracker
    
    init(url: URL, video_size: Binding<CGSize?>, controller: VideoController) {
        self.url = url
        _model = StateObject(wrappedValue: DamusVideoPlayerViewModel(url: url, video_size: video_size, controller: controller))
    }
    
    var body: some View {
        GeometryReader { geo in
            let localFrame = geo.frame(in: .local)
            let centerY = globalCoordinate(localX: 0, localY: localFrame.midY, localGeometry: geo).y
            ZStack {
                AVPlayerView(player: model.player)
                
                if model.is_loading {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(CGSize(width: 1.5, height: 1.5))
                }
                
                if model.has_audio {
                    mute_button
                }
                if model.is_live {
                    live_indicator
                }
            }
            .onChange(of: centerY) { _ in
                update_is_visible(centerY: centerY)
            }
            .onAppear {
                update_is_visible(centerY: centerY)
            }
        }
        .onDisappear {
            model.view_did_disappear()
        }
    }
    
    private func update_is_visible(centerY: CGFloat) {
        let isBelowTop = centerY > 100, /// 100 =~ approx. bottom (y) of ContentView's TabView
            isAboveBottom = centerY < orientationTracker.deviceMajorAxis
        model.set_view_is_visible(isBelowTop && isAboveBottom)
    }
    
    private var mute_icon: String {
        !model.has_audio || model.is_muted ? "speaker.slash" : "speaker"
    }
    
    private var mute_icon_color: Color {
        model.has_audio ? .white : .red
    }
    
    private var mute_button: some View {
        HStack {
            Spacer()
            VStack {
                Spacer()
                
                Button {
                    model.did_tap_mute_button()
                } label: {
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
            }
        }
    }
    
    private var live_indicator: some View {
        VStack {
            HStack {
                Text("LIVE")
                    .bold()
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .padding(.vertical, 5)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.5))
                    )
                    .padding([.top, .leading])
                Spacer()
            }
            Spacer()
        }
    }
}
struct DamusVideoPlayer_Previews: PreviewProvider {
    static var previews: some View {
        DamusVideoPlayer(url: URL(string: "http://cdn.jb55.com/s/zaps-build.mp4")!, video_size: .constant(nil), controller: VideoController())
    }
}
