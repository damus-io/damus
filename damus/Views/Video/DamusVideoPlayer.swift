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
    let style: Style
    let visibility_tracking_method: VisibilityTrackingMethod
    @State var isVisible: Bool = false
    
    init(url: URL, video_size: Binding<CGSize?>, coordinator: DamusVideoCoordinator, style: Style, visibility_tracking_method: VisibilityTrackingMethod = .y_scroll) {
        self.url = url
        let mute: Bool?
        if case .full = style {
            mute = false
        }
        else {
            mute = nil
        }
        _model = StateObject(wrappedValue: DamusVideoPlayerViewModel(url: url, video_size: video_size, coordinator: coordinator, mute: mute))
        self.visibility_tracking_method = visibility_tracking_method
        self.style = style
    }
    
    var body: some View {
        ZStack {
            if case .full = self.style {
                DamusAVPlayerView(player: model.player, controller: model.player_view_controller, show_playback_controls: true)
            }
            if case .preview(let on_tap) = self.style {
                DamusAVPlayerView(player: model.player, controller: model.player_view_controller, show_playback_controls: false)
                    .simultaneousGesture(TapGesture().onEnded({
                        on_tap?()
                    }))
            }
            
            if model.is_loading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(CGSize(width: 1.5, height: 1.5))
            }
            
            if case .preview = self.style {
                if model.has_audio {
                    mute_button
                }
            }
            if model.is_live {
                live_indicator
            }
        }
        .on_visibility_change(perform: { new_visibility in
            model.set_view_is_visible(new_visibility)
        }, method: self.visibility_tracking_method == .generic ? .no_y_scroll_detection : .standard)
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
                Text("LIVE", comment: "Text indicator that the video is a livestream.")
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
    
    enum Style {
        /// A full video player with playback controls
        case full
        /// A style suitable for muted, auto-playing videos on a feed
        case preview(on_tap: (() -> Void)?)
    }
    
    enum VisibilityTrackingMethod {
        /// Detects visibility based on its Y position relative to viewport. Ideal for long feeds
        case y_scroll
        /// Detects visibility based whether the view intersects with the viewport
        case generic
    }
}
struct DamusVideoPlayer_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DamusVideoPlayer(url: URL(string: "http://cdn.jb55.com/s/zaps-build.mp4")!, video_size: .constant(nil), coordinator: DamusVideoCoordinator(), style: .full)
                .environmentObject(OrientationTracker())
                .previewDisplayName("Full video player")
            
            DamusVideoPlayer(url: URL(string: "http://cdn.jb55.com/s/zaps-build.mp4")!, video_size: .constant(nil), coordinator: DamusVideoCoordinator(), style: .preview(on_tap: nil))
                .environmentObject(OrientationTracker())
                .previewDisplayName("Preview video player")
        }
    }
}
