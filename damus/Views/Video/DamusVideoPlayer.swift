//
//  VideoPlayerView.swift
//  damus
//
//  Created by William Casarin on 2023-04-05.
//

import SwiftUI

/// get coordinates in Global reference frame given a Local point & geometry
fileprivate func globalCoordinate(localX x: CGFloat, localY y: CGFloat,
                      localGeometry geo: GeometryProxy) -> CGPoint {
    let localPoint = CGPoint(x: x, y: y)
    return geo.frame(in: .global).origin.applying(
        .init(translationX: localPoint.x, y: localPoint.y)
    )
}

fileprivate extension Double {
    /// Extend Double to decode hours, minutes, and seconds into a human-readable timecode (e.g. "02:41:50").
    var secondsToHumanReadableTimecode: String {
        guard self > 0.0 else { return "00:00" }
        let totalSeconds = UInt64(self)
        let hours = totalSeconds / 3600
        let minutes = totalSeconds % 3600 / 60
        let seconds = totalSeconds % 3600 % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

/// Damus-specific video player that displays controls for seeking, play/pause, volume control, and more.
struct DamusVideoPlayer: View {
    let url: URL
    @ObservedObject var model: VideoPlayerModel
    @Binding var video_size: CGSize?
    @EnvironmentObject private var orientationTracker: OrientationTracker
    @State private var isOptionsPopoverPresented = false
    @State private var isVolumeSliderPresented = false
    @State private var playbackSpeedOption: PlaybackSpeedMenu.PlaybackSpeedOption = .normal
    
    // Track if the video was playing before seeking so we can intelligently resume playing after changing the seek time
    @State private var wasPlayingBeforeSeek = true
    
    @State var showControls: Bool
    
    @State var onVideoTapped: (() -> Void)?
    
    var isMuted: Bool {
        return model.has_audio == false || model.muted
    }
    
    var muteIconColor: Color {
        switch self.model.has_audio {
        case .none:
            return .white
        case .some(let has_audio):
            return has_audio ? .white : .red
        }
    }
    
    func hideControls() -> Self {
        showControls = false
        return self
    }
    
    private func VideoButton(imageName: String) -> some View {
        ZStack {
            Circle()
                .opacity(0.2)
                .frame(width: 32, height: 32)
                .foregroundColor(.black)
            
            Image(systemName: imageName)
                .padding([.leading, .trailing], 1)
                .padding([.top, .bottom], nil)
                .foregroundColor(.white)
        }
    }
    
    private var VolumeButton: some View {
        func imageName() -> String {
            if isMuted {
                return "speaker.slash"
            }
            else {
                switch model.volume {
                case ..<0.01:
                    return "speaker.slash.fill"
                case ..<0.3:
                    return "speaker.wave.1.fill"
                case ..<0.6:
                    return "speaker.wave.2.fill"
                default:
                    return "speaker.wave.3.fill"
                }
            }
        }
        return VideoButton(imageName: imageName())
            .onTapGesture {
                isVolumeSliderPresented.toggle()
                model.muted.toggle()
            }
    }
    
    private var PlayPauseButton: some View {
        VideoButton(imageName: model.play ? "pause" : "play")
            .onTapGesture {
                self.model.play.toggle()
            }
    }
    
    private var SettingsButton: some View {
        VideoButton(imageName: isOptionsPopoverPresented ? "gearshape.fill" : "gearshape")
            .onTapGesture {
                isOptionsPopoverPresented.toggle()
            }
            .popover(isPresented: $isOptionsPopoverPresented,
                     attachmentAnchor: .point(.top),
                     arrowEdge: .top) {
                if #available(iOS 16.4, macOS 13.3, *) {
                    OptionsMenu
                        .presentationCompactAdaptation(.popover)
                }
                else {
                    OptionsMenu
                }
            }
    }
    
    private var FullscreenButton: some View {
        VideoButton(imageName: self.model.contentMode == .scaleAspectFill ?  "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
            .onTapGesture {
                switch self.model.contentMode {
                case .scaleAspectFit:
                    self.model.contentMode = .scaleAspectFill
                case .scaleAspectFill:
                    self.model.contentMode = .scaleAspectFit
                default:
                    break
                }
            }
    }
    
    private var VideoTime: some View {
        Text("\(self.model.currentTime.secondsToHumanReadableTimecode) / \(self.model.totalDuration.secondsToHumanReadableTimecode)")
            .padding([.leading, .trailing], 1)
            .padding([.top, .bottom], nil)
            .monospacedDigit()
            .foregroundColor(muteIconColor)
            .fixedSize(horizontal: true, vertical: true)
            .onTapGesture {
                self.model.play.toggle()
            }
    }
    
    private var OptionsMenu: some View {
        PlaybackSpeedMenu(selected: $playbackSpeedOption)
            .onChange(of: playbackSpeedOption) {
                self.model.playbackRate = $0.rawValue
            }
    }
    
    var body: some View {
        GeometryReader { geo in
            let localFrame = geo.frame(in: .local)
            let centerY = globalCoordinate(localX: 0, localY: localFrame.midY, localGeometry: geo).y
            let delta = localFrame.height / 2
            
            ZStack(alignment: .bottomTrailing) {
                
                VideoPlayer(url: url, model: model)
                    .zIndex(0.0)
//                    .onAppear {
//                        self.model.start()
//                    }
                    .onTapGesture {
                        if let tapHandler = onVideoTapped {
                            tapHandler()
                        }
                        else {
                            showControls.toggle()
                        }
                    }
                
                if showControls {       // TODO: Animate controls in/out
                    Group {     // Group for all overlayed controls
                        VStack(alignment: .trailing) {
                            // Volume slider
                            if isVolumeSliderPresented {    // TODO: Animate volume slider in/out
                                VolumeSlider(volume: $model.volume)
                                { editing in
                                    // Changing the volume value unmutes
                                    if self.model.muted {
                                        _ = self.model.set(muted: false)
                                    }
                                }
                                .frame(width: 12, height: 130)
                                .padding([.leading, .trailing], 8)
                                .padding([.top, .bottom], 1)
                            }
                            
                            // Seek slider
                            SeekSlider(time: Binding(get: { self.model.currentTime },
                                                     set: { _ in }),
                                       totalDuration: self.model.totalDuration)
                            { editing in
                                if editing {
                                    self.wasPlayingBeforeSeek = model.play
                                    model.stop()
                                }
                            }
                        onTimeFinalized: { time in
                            _ = model.set(seekSeconds: time)
                            if self.wasPlayingBeforeSeek {
                                model.start()
                            }
                        }
                        .padding([.leading, .trailing], 8)
                        .frame(height: 10)
                            
                            ZStack(alignment: .bottomTrailing) {     // Group bottom elements
                                PlayPauseButton
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding([.leading, .trailing], 8)
                                
                                VideoTime
                                    .frame(maxWidth: .infinity, alignment: .center)
                                
                                // Settings, Fullscreen, and Volume
                                HStack {
                                    // TODO: Changing playback speed is currently broken for unknown reasons.
                                    SettingsButton
                                    
                                    if model.has_audio == true {
                                        FullscreenButton
                                        
                                        VolumeButton
                                            .padding([.trailing], 8)
                                    }
                                    else {
                                        FullscreenButton
                                        // Keep button spacing even if the VolumeButton is not present
                                            .padding([.trailing], 32 + 16)
                                    }
                                }
                            }
                        }
                    }
                    .zIndex(1.0)
                }
            }
            .onChange(of: model.size) { size in
                guard let size else {
                    return
                }
                video_size = size
            }
            .onChange(of: centerY) { _ in
                /// pause video when it is scrolled beyond visible range
                let isBelowTop = centerY + delta > 100, /// 100 =~ approx. bottom (y) of ContentView's TabView
                    isAboveBottom = centerY - delta < orientationTracker.deviceMajorAxis
                if isBelowTop && isAboveBottom {
                    model.start()
                } else {
                    model.stop()
                }
            }
        }
        .onDisappear {
            model.stop()
        }
    }
}
fileprivate extension DamusVideoPlayer {
    struct PlaybackSpeedMenu : View {
        enum PlaybackSpeedOption : Float, CaseIterable, Identifiable {
            case half           = 0.5
            case normal         = 1.0
            case oneAndQuarter  = 1.25
            case oneAndHalf     = 1.5
            case double         = 2.0
            var id: String {
                return String(format: "%1.2f", arguments: [self.rawValue])
            }
            var displayName: String {
                switch self {
                case .half:             return "0.5x"
                case .normal:           return "1x"
                case .oneAndQuarter:    return "1.25x"
                case .oneAndHalf:       return "1.5x"
                case .double:           return "2.0x"
                }
            }
        }
        
        @Binding var selected: PlaybackSpeedOption
        
        var body: some View {
            VStack {
                ForEach(PlaybackSpeedOption.allCases) { option in
                    HStack {
                        Text(verbatim: option.displayName)
                            .frame(minWidth: 150, maxWidth: .infinity, alignment: .leading)
                            .padding()
                        Image(systemName: (self.selected == option) ? "checkmark" : "circle")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding()
                    }
                    .onTapGesture {
                        self.selected = option
                    }
                }
            }
            .frame(minWidth: 200)
        }
    }
}
fileprivate extension DamusVideoPlayer {
    /// A vertical volume slider ranging from 0.0 (silent) to 1.0 (full volume).
    /// `onEditingChanged` is called when the user begins or ends editing the volume value using this slider
    /// Inspired by [pratikg29's VerticalVolumeSlider](https://github.com/pratikg29/Custom-Slider-Control/blob/main/AppleMusicSlider/AppleMusicSlider/VerticalVolumeSlider.swift)
    struct VolumeSlider : View {
        @Binding var volume: Float
        @State private var localRealProgress: Float = 0
        @State private var localTempProgress: Float = 0
        @GestureState private var isEditing: Bool = false
        let onEditingChanged: (Bool) -> Void
        
        var body: some View {
            GeometryReader { bounds in
                ZStack {
                    GeometryReader { geo in
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: bounds.size.width, style: .continuous)
                                .fill(Color.black)
                            RoundedRectangle(cornerRadius: bounds.size.width, style: .continuous)
                                .foregroundColor(.accentColor)
                                .mask({
                                    VStack {
                                        Spacer(minLength: 0)
                                        Rectangle()
                                            .frame(height: max(geo.size.height * CGFloat((localRealProgress + localTempProgress)), 0),
                                                   alignment: .leading)
                                    }
                                })
                        }
                        .clipped()
                    }
                }
                .frame(width: bounds.size.width, height: bounds.size.height, alignment: .center)
                .gesture(DragGesture(minimumDistance: 8, coordinateSpace: .local)
                    .updating($isEditing) { value, state, transaction in
                        state = true
                    }
                    .onChanged { gesture in
                        localTempProgress = Float(-gesture.translation.height / bounds.size.height)
                        volume = max(min(localRealProgress + localTempProgress, 1.0), 0.0)
                    }.onEnded { value in
                        localRealProgress = max(min(localRealProgress + localTempProgress, 1), 0)
                        localTempProgress = 0
                    })
                .onChange(of: isEditing) { editing in
                    onEditingChanged(editing)
                }
                .onAppear {
                    localRealProgress = volume
                }
                .onChange(of: volume) { newValue in
                    if !(isEditing) {
                        localRealProgress = volume
                    }
                }
            }
            .frame(alignment: .center)
        }
    }
}
fileprivate extension DamusVideoPlayer {
    /// A seek time slider ranging from 0.0 (beginning) to `totalDuration` at the end.
    /// `onEditingChanged` is called when the user begins or ends editing the current play location using this slider.
    /// `onTimeFinalized` is called when the user end editing and the new time has been calculated, ready for seek.
    /// Inspired by [pratikg29's VerticalVolumeSlider](https://github.com/pratikg29/Custom-Slider-Control/blob/main/AppleMusicSlider/AppleMusicSlider/VerticalVolumeSlider.swift)
    struct SeekSlider : View {
        @Binding var time: Double
        @State private var localRealProgress: Double = 0
        @State private var localTempProgress: Double = 0
        @GestureState private var isEditing: Bool = false
        let totalDuration: Double
        let onEditingChanged: (Bool) -> Void
        let onTimeFinalized: (Double) -> Void
        
        var body: some View {
            GeometryReader { bounds in
                ZStack {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: bounds.size.height, style: .continuous)
                                .fill(Color.black)
                            RoundedRectangle(cornerRadius: bounds.size.height, style: .continuous)
                                .foregroundColor(.accentColor)
                                .mask({
                                    HStack {
                                        Rectangle()
                                            .frame(width: max(geo.size.width * CGFloat((localRealProgress + localTempProgress)), 0),
                                                   alignment: .leading)
                                        Spacer(minLength: 0)
                                    }
                                })
                        }
                        .clipped()
                    }
                }
                .frame(width: bounds.size.width, height: bounds.size.height, alignment: .center)
                .gesture(DragGesture(minimumDistance: 8, coordinateSpace: .local)
                    .updating($isEditing) { value, state, transaction in
                        state = true
                    }
                    .onChanged { gesture in
                        localTempProgress = Double(gesture.translation.width / bounds.size.width)
                        time = max(min(localRealProgress + localTempProgress, 1.0), 0.0)
                    }.onEnded { value in
                        localRealProgress = max(min(localRealProgress + localTempProgress, 1.0), 0)
                        localTempProgress = 0
                        
                        onTimeFinalized(localRealProgress * totalDuration)
                    })
                .onChange(of: isEditing) { editing in
                    onEditingChanged(editing)
                }
                .onAppear {
                    localRealProgress = time / totalDuration
                }
                .onChange(of: time) { newValue in
                    if !(isEditing) {
                        localRealProgress = time / totalDuration
                    }
                }
            }
            .frame(alignment: .center)
        }
    }
}

struct DamusVideoPlayer_Previews: PreviewProvider {
    @StateObject static var model: VideoPlayerModel = VideoPlayerModel()
    
    static var previews: some View {
        DamusVideoPlayer(url: URL(string: "http://cdn.jb55.com/s/zaps-build.mp4")!, model: model, video_size: .constant(nil), showControls: true)
            .environmentObject(OrientationTracker())
//            .previewInterfaceOrientation(.landscapeLeft)
    }
}
