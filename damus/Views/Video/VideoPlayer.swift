//
//  VideoPlayer.swift
//  damus
//
//  Created by William Casarin on 2023-05-25.
//

import Foundation
//
//  VideoPlayer.swift
//  VideoPlayer
//
//  Created by Gesen on 2019/7/7.
//  Copyright © 2019 Gesen. All rights reserved.
//

import AVFoundation
import Combine
import GSPlayer
import SwiftUI

public enum VideoState {
    /// From the first load to get the first frame of the video
    case loading
    
    /// Playing now
    case playing(totalDuration: Double)
    
    /// Pause, will be called repeatedly when the buffer progress changes
    case paused(playProgress: Double, bufferProgress: Double)
    
    /// An error occurred and cannot continue playing
    case error(NSError)
}

enum VideoHandler {
    case onBufferChanged((Double) -> Void)
    case onPlayToEndTime(() -> Void)
    case onReplay(() -> Void)
    case onStateChanged((VideoState) -> Void)
}
    
@MainActor
public class VideoPlayerModel: ObservableObject {
    @Published var autoReplay = true
    @Published var muted = true
    @Published var play = true
    @Published var size: CGSize? = nil
    @Published var has_audio: Bool? = nil
    @Published var contentMode: UIView.ContentMode = .scaleAspectFill
    @Published var currentTime = 0.0
    @Published var playbackRate: Float = 1.0
    @Published var volume: Float = 1.0
    // Split out a deliberate stream for *setting* currentTime manually, that way system-driven updates don't cause infinite loops and strange fighting behavior.
    let currentTimeSubject = PassthroughSubject<Double, Never>()
    
    var totalDuration: Double = 0.0
    
    var handlers: [VideoHandler] = []
    
    init() {
    }
    
    func stop() {
        self.play = false
    }
    
    func start() {
        self.play = true
    }
    
    func mute() {
        self.muted = true
    }
    
    func unmute() {
        self.muted = false
    }
    
    /// Whether the video will be automatically replayed until the end of the video playback.
    func set(autoReplay value: Bool) -> Self {
        autoReplay = value
        return self
    }
    
    /// Whether the video is muted, only for this instance.
    func set(muted value: Bool) -> Self {
        muted = value
        return self
    }
    
    func set(volume value: Float) -> Self {
        volume = value
        return self
    }
    
    func set(playbackRate value: Float) -> Self {
        self.playbackRate = value
        return self
    }
    
    func set(seekSeconds: Double) -> Self {
        self.currentTime = seekSeconds
        self.currentTimeSubject.send(self.currentTime)
        return self
    }
    
    /// A string defining how the video is displayed within an AVPlayerLayer bounds rect.
    /// scaleAspectFill -> resizeAspectFill, scaleAspectFit -> resizeAspect, other -> resize
    func set(contentMode value: UIView.ContentMode) -> Self {
        contentMode = value
        return self
    }
    
    /// Trigger a callback when the buffer progress changes,
    /// the value is between 0 and 1.
    func onBufferChanged(_ handler: @escaping (Double) -> Void) -> Self {
        self.handlers.append(.onBufferChanged(handler))
        return self
    }
    
    /// Playing to the end.
    func onPlayToEndTime(_ handler: @escaping () -> Void) -> Self {
        self.handlers.append(.onPlayToEndTime(handler))
        return self
    }
    
    /// Replay after playing to the end.
    func onReplay(_ handler: @escaping () -> Void) -> Self {
        self.handlers.append(.onReplay(handler))
        return self
    }
    
    /// Playback status changes, such as from play to pause.
    func onStateChanged(_ handler: @escaping (VideoState) -> Void) -> Self {
        self.handlers.append(.onStateChanged(handler))
        return self
    }
}

@available(iOS 13, *)
public struct VideoPlayer {
    private(set) var url: URL
    
    @ObservedObject var model: VideoPlayerModel
    
    /// Init video player instance.
    /// - Parameters:
    ///   - url: http/https URL
    ///   - play: play/pause
    ///   - time: current time
    public init(url: URL, model: VideoPlayerModel) {
        self.url = url
        self._model = ObservedObject(wrappedValue: model)
    }
}

@available(iOS 13, *)
public extension VideoPlayer {
    
    /// Set the preload size, the default value is 1024 * 1024, unit is byte.
    static var preloadByteCount: Int {
        get { VideoPreloadManager.shared.preloadByteCount }
        set { VideoPreloadManager.shared.preloadByteCount = newValue }
    }
    
    /// Set the video urls to be preload queue.
    /// Preloading will automatically cache a short segment of the beginning of the video
    /// and decide whether to start or pause the preload based on the buffering of the currently playing video.
    /// - Parameter urls: URL array
    static func preload(urls: [URL]) {
        VideoPreloadManager.shared.set(waiting: urls)
    }
    
    /// Set custom http header, such as token.
    static func customHTTPHeaderFields(transform: @escaping (URL) -> [String: String]?) {
        VideoLoadManager.shared.customHTTPHeaderFields = transform
    }
    
    /// Get the total size of the video cache.
    static func calculateCachedSize() -> UInt {
        return VideoCacheManager.calculateCachedSize()
    }
    
    /// Clean up all caches.
    static func cleanAllCache() {
        try? VideoCacheManager.cleanAllCache()
    }
}

fileprivate extension AVPlayer {
    var videoSize: CGSize? {
        get async {
            let res = Task.detached(priority: .background) {
                return self.currentImage?.size
            }
            return await res.value
        }
    }
    
    var hasAudio: Bool {
        get async {
            let tracks = try? await self.currentItem?.asset.load(.tracks)
            return tracks?.filter({ t in t.mediaType == .audio }).first != nil
        }
    }
}

@available(iOS 13, *)
extension VideoPlayer: UIViewRepresentable {
    public func makeUIView(context: Context) -> VideoPlayerView {
        let uiView = VideoPlayerView()
        
        uiView.playToEndTime = { [weak model] in
            guard let model else { return }
            if model.autoReplay == false {
                model.play = false
            }
            DispatchQueue.main.async {
                for handler in model.handlers {
                    if case .onPlayToEndTime(let cb) = handler {
                        cb()
                    }
                }
            }
        }
        
        uiView.contentMode = self.model.contentMode
        
        uiView.replay = { [weak model] in
            guard let model else { return }
            DispatchQueue.main.async {
                for handler in model.handlers {
                    if case .onReplay(let cb) = handler {
                        cb()
                    }
                }
            }
        }
        
        uiView.stateDidChanged = { [weak model, unowned uiView] _ in
            guard let model else { return }
            let state: VideoState = uiView.videoState
            
            if case .playing = uiView.videoState {
                model.totalDuration = uiView.totalDuration
                context.coordinator.startObserver(uiView: uiView)
                if let player = uiView.player {
                    Task {
                        let has_audio = await player.hasAudio
                        let size = await player.videoSize
                        Task { @MainActor in
                            if let size {
                                model.size = size
                            }
                            model.has_audio = has_audio
                        }
                    }
                }
            }
            
            DispatchQueue.main.async { [weak model] in
                guard let model else { return }
                for handler in model.handlers {
                    if case .onStateChanged(let cb) = handler {
                        cb(state)
                    }
                }
            }
        }
        
        // Split this out because calling `uiView.play(for:)` will initialize the coordinator, which will result in an initialization loop.
        context.coordinator.disposeSet.insert(context.coordinator.videoPlayer.model.$play.sink { [weak model, unowned uiView] play in
            if play {
                uiView.resume()
                // We have to re-set the AVPlayer.rate property because internally AVPlayer sets this value to 0.0 for pausing.
                guard let model else { return }
                uiView.player?.rate = model.playbackRate
            }
            else {
                uiView.pause(reason: .userInteraction)
            }
        })
        
        uiView.play(for: self.url)
        
        return uiView
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public func updateUIView(_ uiView: VideoPlayerView, context: Context) {
        // This method is called A LOT for this view, so model properties have been moved to publishers to allow for event-driven changes instead of performance heavy checks here.
    }
    
    public static func dismantleUIView(_ uiView: VideoPlayerView, coordinator: VideoPlayer.Coordinator) {
        uiView.pause(reason: .hidden)
    }
    
    public class Coordinator: NSObject {
        var videoPlayer: VideoPlayer
        var observingURL: URL?
        var observer: Any?
        var observerBuffer: Double?
        var disposeSet: Set<AnyCancellable> = []

        init(_ videoPlayer: VideoPlayer) {
            self.videoPlayer = videoPlayer
        }
        
        @MainActor
        func startObserver(uiView: VideoPlayerView) {
            guard observer == nil else { return }
            
            disposeSet.insert(videoPlayer.model.$muted.sink { [unowned uiView] muted in
                uiView.isMuted = muted
            })
            
            disposeSet.insert(videoPlayer.model.$autoReplay.sink { [unowned uiView] autoReplay in
                uiView.isAutoReplay = autoReplay
            })
            
            disposeSet.insert(videoPlayer.model.$contentMode.sink { [unowned uiView] mode in
                uiView.contentMode = mode
            })
            
            disposeSet.insert(videoPlayer.model.$playbackRate.sink { [unowned uiView] rate in
                uiView.player?.rate = rate
            })
            
            disposeSet.insert(videoPlayer.model.$volume.sink { [unowned uiView] volume in
                uiView.volume = Double(volume)
            })
            
            disposeSet.insert(videoPlayer.model.currentTimeSubject.sink { [unowned uiView] seconds in
                uiView.seek(to: CMTime(seconds: seconds, preferredTimescale: uiView.player?.currentTime().timescale ?? 1000))
            })
            
            observer = uiView.addPeriodicTimeObserver(forInterval: .init(seconds: 0.25, preferredTimescale: 60)) { [weak self, unowned uiView] time in
                guard let self else { return }
                
                Task { @MainActor in
                    self.videoPlayer.model.currentTime = uiView.currentDuration
                }
                
                self.updateBuffer(uiView: uiView)
            }
        }
        
        func stopObserver(uiView: VideoPlayerView) {
            guard let observer else { return }
            
            uiView.removeTimeObserver(observer)
            
            self.observer = nil
        }
        
        func clean() {
            self.observingURL = nil
            self.observer = nil
            self.observerBuffer = nil
            self.disposeSet = []
        }
        
        @MainActor
        func updateBuffer(uiView: VideoPlayerView) {
            let bufferProgress = uiView.bufferProgress
            guard bufferProgress != observerBuffer else { return }
            
            for handler in videoPlayer.model.handlers {
                if case .onBufferChanged(let cb) = handler {
                    DispatchQueue.main.async {
                        cb(bufferProgress)
                    }
                }
            }
            
            observerBuffer = bufferProgress
        }
    }
}

private extension VideoPlayerView {
    var videoState: VideoState {
        switch state {
        case .none, .loading:
            return .loading
        case .playing:
            return .playing(totalDuration: totalDuration)
        case .paused(let p, let b):
            return .paused(playProgress: p, bufferProgress: b)
        case .error(let error):
            return .error(error)
        }
    }
}
