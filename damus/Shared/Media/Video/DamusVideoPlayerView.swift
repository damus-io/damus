//
//  DamusVideoPlayerView.swift
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

/// A feature-rich, generic video player view that plays along well with the multi-video coordinator
struct DamusVideoPlayerView: View {
    let url: URL
    @ObservedObject var model: DamusVideoPlayer
    let style: Style
    let main_state_requestor_id: UUID = UUID()
    
    @State var is_visible: Bool = false {
        didSet {
            if self.is_visible {
                // We are visible, request main stage
                video_coordinator.request_main_stage(
                    DamusVideoCoordinator.MainStageRequest(
                        requestor_id: self.main_state_requestor_id,
                        layer_context: self.view_layer,
                        player: self.model,
                        main_stage_granted: self.main_stage_granted
                    )
                )
            }
            else {
                // We are no longer visible, give up the main stage
                video_coordinator.give_up_main_stage(request_id: self.main_state_requestor_id)
            }
        }
    }
    
    /// The context this video player is in.
    @Environment(\.view_layer_context) var view_layer_context
    /// The video coordinator in this environment
    let video_coordinator: DamusVideoCoordinator
    
    var view_layer: ViewLayerContext {
        return view_layer_context ?? .normal_layer
    }
    
    init(url: URL, coordinator: DamusVideoCoordinator, style: Style) {
        self.url = url
        self.model = coordinator.get_player(for: url)
        self.video_coordinator = coordinator
        self.style = style
    }
    
    init(model: DamusVideoPlayer, coordinator: DamusVideoCoordinator, style: Style) {
        self.url = model.url
        self.model = model
        self.video_coordinator = coordinator
        self.style = style
    }
    
    var body: some View {
        ZStack {
            switch self.style {
                case .full:
                    DamusVideoPlayer.BaseView(player: model, show_playback_controls: true)
                case .preview(on_tap: let on_tap), .no_controls(on_tap: let on_tap):
                    ZStack {
                        placeholder_underlay
                        DamusVideoPlayer.BaseView(player: model, show_playback_controls: false)
                    }
                    .modifier(FullscreenTapModifier(onTap: on_tap))
            }
            
            if case .loading = model.load_state, model.is_playing == false {
                loading_overlay
            }
            
            if case .failed(let message) = model.load_state {
                error_overlay(message: message)
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
        .on_visibility_change(perform: { new_is_visible in
            self.is_visible = new_is_visible
        }, method: self.visibility_tracking_method)
        // Keep spinner visible above poster/last frame; allow interactions to hit the view.
    }
    
    private var visibility_tracking_method: VisibilityTracker.Method {
        switch self.view_layer {
            case .normal_layer:
                return .standard
            case .full_screen_layer:
                return .no_y_scroll_detection
        }
    }
    
    func main_stage_granted() {
        switch self.style {
            case .full, .no_controls:
                self.model.is_muted = false
            case .preview:
                self.model.is_muted = true
        }
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
                ZStack {
                    Circle()
                        .opacity(0.2)
                        .frame(width: 32, height: 32)
                        .foregroundColor(.black)
    
                    Image(systemName: mute_icon)
                        .padding()
                        .foregroundColor(mute_icon_color)
                }
                .highPriorityGesture(TapGesture().onEnded {
                    model.is_muted.toggle()
                })
                Spacer()
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
    
    private var loading_overlay: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 8) {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .scaleEffect(CGSize(width: 1.5, height: 1.5))
                    Text("Loading…")
                        .foregroundColor(.white)
                        .font(.caption)
                }
                .padding(12)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                Spacer()
            }
            Spacer()
        }
    }
    
    private func error_overlay(message: String) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(spacing: 10) {
                    Text("Unable to play video")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(message)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .lineLimit(2)
                    Button(action: {
                        model.reinitializePlayer()
                    }, label: {
                        Text("Retry")
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.white.opacity(0.2))
                            .foregroundColor(.white)
                            .clipShape(Capsule())
                    })
                }
                .padding(14)
                .background(Color.black.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                Spacer()
            }
            Spacer()
        }
    }
    
    private var placeholder_underlay: some View {
        Group {
            if let poster = model.posterImage {
                Image(uiImage: poster)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            } else {
                Color.black.opacity(0.4)
            }
        }
    }
    
    // MARK: - Helper structures
    
    enum Style {
        /// A full video player with playback controls
        case full
        /// A style suitable for muted, auto-playing videos on a feed
        case preview(on_tap: (() -> Void)?)
        /// A video player without any playback controls, suitable if using custom controls elsewhere.
        case no_controls(on_tap: (() -> Void)?)
    }
}

private struct FullscreenTapModifier: ViewModifier {
    let onTap: (() -> Void)?
    
    func body(content: Content) -> some View {
        guard let onTap else { return AnyView(content) }
        return AnyView(
            content.highPriorityGesture(TapGesture().onEnded({
                onTap()
            }))
        )
    }
}
struct DamusVideoPlayer_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            DamusVideoPlayerView(url: URL(string: "http://cdn.jb55.com/s/zaps-build.mp4")!, coordinator: DamusVideoCoordinator(), style: .full)
                .environmentObject(OrientationTracker())
                .environmentObject(DamusVideoCoordinator())
                .previewDisplayName("Full video player")
            
            DamusVideoPlayerView(url: URL(string: "http://cdn.jb55.com/s/zaps-build.mp4")!, coordinator: DamusVideoCoordinator(), style: .preview(on_tap: nil))
                .environmentObject(OrientationTracker())
                .environmentObject(DamusVideoCoordinator())
                .previewDisplayName("Preview video player")
        }
    }
}
