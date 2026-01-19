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

    @State private var showPlayPauseFeedback: Bool = false
    @State private var feedbackIcon: String = "play.fill"
    @State private var showInlineControls: Bool = true
    
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
            player_base

            if model.is_loading {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
                    .scaleEffect(CGSize(width: 1.5, height: 1.5))
            }

            overlay_for_style

            if model.is_live {
                live_indicator
            }

            if showPlayPauseFeedback {
                ZStack {
                    Circle()
                        .fill(Color.black.opacity(0.6))
                        .frame(width: 100, height: 100)
                    Image(systemName: feedbackIcon)
                        .font(.system(size: 50))
                        .foregroundColor(.white)
                }
                .transition(.opacity)
            }
        }
        .contentShape(Rectangle()) // Ensure the entire view accepts hit testing
        .modifier(TapGestureModifier(style: style, onTap: handle_primary_tap))
        .on_visibility_change(perform: { new_is_visible in
            self.is_visible = new_is_visible
        }, method: self.visibility_tracking_method)
        .onChange(of: model.is_playing) { newValue in
            showFeedback(isPlaying: newValue)
            manageInlineControlsVisibility(for: newValue)
        }
    }
    
    private var player_base: some View {
        Group {
            switch self.style {
                case .full:
                    DamusVideoPlayer.BaseView(player: model, show_playback_controls: true)
                case .preview, .no_controls:
                    ZStack {
                        DamusVideoPlayer.BaseView(player: model, show_playback_controls: false)
                        // Transparent overlay to catch taps before AVPlayerViewController consumes them
                        Color.clear
                            .contentShape(Rectangle())
                    }
            }
        }
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
    
    private var overlay_for_style: some View {
        Group {
            switch self.style {
                case .full:
                    EmptyView()
                case .preview(on_tap: let on_tap):
                    preview_overlay(on_fullscreen: on_tap)
                case .no_controls(on_tap: let on_tap):
                    // Provide fullscreen control even when custom controls are elsewhere.
                    if let on_tap {
                        fullscreen_button(on_tap: on_tap)
                            .padding()
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    }
            }
        }
    }
    
    private func handle_primary_tap() {
        switch self.style {
            case .preview, .no_controls:
                // Toggle play/pause for inline and fullscreen no-controls variants.
                guard !model.is_loading else { return }
                let new_state = !model.is_playing
                model.is_playing = new_state
                if new_state {
                    // A deliberate play tap should also unmute, per HIG expectations.
                    model.is_muted = false
                }
            case .full:
                break
        }
    }

    private func showFeedback(isPlaying: Bool) {
        feedbackIcon = isPlaying ? "play.fill" : "pause.fill"
        withAnimation(.easeInOut(duration: 0.15)) {
            showPlayPauseFeedback = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            withAnimation(.easeInOut(duration: 0.15)) {
                showPlayPauseFeedback = false
            }
        }
    }
    
    private func preview_overlay(on_fullscreen: (() -> Void)?) -> some View {
        ZStack {
            if model.has_audio {
                mute_button
            }
            
            VStack {
                HStack {
                    Spacer()
                    if let on_fullscreen {
                        fullscreen_button(on_tap: on_fullscreen)
                    }
                }
                Spacer()
                HStack {
                    if showInlineControls {
                        Spacer()
                        HStack(spacing: 10) {
                            play_pause_button
                            progress_bar
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .frame(maxWidth: 260) // Keep inline controls compact for aesthetics.
                        .background(.thinMaterial)
                        .clipShape(Capsule())
                        Spacer()
                    }
                }
                .padding([.horizontal, .bottom], 12)
            }
        }
    }
    
    private var play_pause_button: some View {
        Button(action: {
            model.is_playing.toggle()
        }, label: {
            Image(systemName: model.is_playing ? "pause.fill" : "play.fill")
                .frame(width: 44, height: 44)
                .foregroundColor(.white)
        })
        .buttonStyle(.plain)
        .accessibilityLabel(model.is_playing ? Text("Pause video") : Text("Play video"))
    }
    
    private var progress_bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.22))
                Capsule()
                    .fill(Color.white)
                    .frame(width: geo.size.width * progress_fraction)
                    .animation(.easeInOut(duration: 0.15), value: progress_fraction)
            }
        }
        .frame(height: 4)
        .accessibilityLabel(Text("Playback progress"))
        .accessibilityValue(Text(progress_accessibility_value))
    }
    
    private var progress_fraction: CGFloat {
        guard
            let duration = model.duration,
            duration > 0,
            duration.isFinite,
            model.current_time.isFinite
        else { return 0 }
        let fraction = model.current_time / duration
        return CGFloat(min(max(fraction, 0), 1))
    }
    
    private var progress_accessibility_value: String {
        guard
            let duration = model.duration,
            duration > 0,
            duration.isFinite,
            model.current_time.isFinite
        else { return "0 percent" }
        // Prevent NaN/Inf crashes on zero or indefinite durations.
        let percent = Int((model.current_time / duration) * 100)
        return "\(percent) percent"
    }
    
    private func manageInlineControlsVisibility(for isPlaying: Bool) {
        // Keep controls visible when paused; auto-hide shortly after play starts.
        if !isPlaying {
            showInlineControls = true
            return
        }
        showInlineControls = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            // Avoid hiding if playback stopped or view changed state.
            if model.is_playing {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showInlineControls = false
                }
            }
        }
    }
    
    private var mute_button: some View {
        HStack {
            VStack {
                Button(action: {
                    model.is_muted.toggle()
                }, label: {
                    ZStack {
                        Circle()
                            .fill(Color.black.opacity(0.5))
                            .frame(width: 44, height: 44)
                        Image(systemName: mute_icon)
                            .foregroundColor(mute_icon_color)
                    }
                })
                .buttonStyle(.plain)
                .padding([.top, .leading], 8)
                .accessibilityLabel(model.is_muted ? Text("Unmute video") : Text("Mute video"))
                Spacer()
            }
            Spacer()
        }
    }
    
    private func fullscreen_button(on_tap: @escaping () -> Void) -> some View {
        Button(action: {
            on_tap()
        }, label: {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: 44, height: 44)
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .foregroundColor(.white)
            }
        })
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Enter full screen"))
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

// MARK: - Tap Gesture Modifier

private struct TapGestureModifier: ViewModifier {
    let style: DamusVideoPlayerView.Style
    let onTap: () -> Void

    func body(content: Content) -> some View {
        switch style {
        case .preview, .no_controls:
            // Handle taps locally to ensure reliable play/pause toggling
            content.onTapGesture {
                onTap()
            }
        case .full:
            // Full has native controls
            content
        }
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
