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
    @Published var autoReplay: Bool = true
    @Published var muted: Bool = true
    @Published var play: Bool = true
    @Published var size: CGSize? = nil
    @Published var has_audio: Bool? = nil
    @Published var contentMode: UIView.ContentMode = .scaleAspectFill
    
    fileprivate var time: CMTime?
    
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
    func autoReplay(_ value: Bool) -> Self {
        autoReplay = value
        return self
    }
    
    /// Whether the video is muted, only for this instance.
    func mute(_ value: Bool) -> Self {
        muted = value
        return self
    }
    
    /// A string defining how the video is displayed within an AVPlayerLayer bounds rect.
    /// scaleAspectFill -> resizeAspectFill, scaleAspectFit -> resizeAspect, other -> resize
    func contentMode(_ value: UIView.ContentMode) -> Self {
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

func get_video_size(player: AVPlayer) async -> CGSize? {
    let res = Task.detached(priority: .background) {
        return player.currentImage?.size
    }
    return await res.value
}

func video_has_audio(player: AVPlayer) async -> Bool {
    let tracks = try? await player.currentItem?.asset.load(.tracks)
    return tracks?.filter({ t in t.mediaType == .audio }).first != nil
}

@available(iOS 13, *)
extension VideoPlayer: UIViewRepresentable {
    
    public func makeUIView(context: Context) -> VideoPlayerView {
        let uiView = VideoPlayerView()
        
        uiView.playToEndTime = {
            if self.model.autoReplay == false {
                self.model.play = false
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
        
        uiView.replay = {
            DispatchQueue.main.async {
                for handler in model.handlers {
                    if case .onReplay(let cb) = handler {
                        cb()
                    }
                }
            }
        }
        
        uiView.stateDidChanged = { [unowned uiView] _ in
            let state: VideoState = uiView.convertState()
            
            if case .playing = state {
                context.coordinator.startObserver(uiView: uiView)
                
                if let player = uiView.player {
                    Task {
                        let has_audio = await video_has_audio(player: player)
                        let size = await get_video_size(player: player)
                        Task { @MainActor in
                            if let size {
                                self.model.size = size
                            }
                            self.model.has_audio = has_audio
                        }
                    }
                }
                
            } else {
                context.coordinator.stopObserver(uiView: uiView)
            }
            
            DispatchQueue.main.async {
                for handler in model.handlers {
                    if case .onStateChanged(let cb) = handler {
                        cb(state)
                    }
                }
            }
        }
        
        return uiView
    }
    
    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    public func updateUIView(_ uiView: VideoPlayerView, context: Context) {
        if context.coordinator.observingURL != url {
            context.coordinator.clean()
            context.coordinator.observingURL = url
        }
        
        if model.play {
            uiView.play(for: url)
        } else {
            uiView.pause(reason: .userInteraction)
        }
        
        uiView.isMuted = model.muted
        uiView.isAutoReplay = model.autoReplay
        
        if let observerTime = context.coordinator.observerTime, let modelTime = model.time,
           modelTime != observerTime && modelTime.isValid && modelTime.isNumeric {
            uiView.seek(to: modelTime, completion: { _ in })
        }
    }
    
    public static func dismantleUIView(_ uiView: VideoPlayerView, coordinator: VideoPlayer.Coordinator) {
        uiView.pause(reason: .hidden)
    }
    
    public class Coordinator: NSObject {
        var videoPlayer: VideoPlayer
        var observingURL: URL?
        var observer: Any?
        var observerTime: CMTime?
        var observerBuffer: Double?

        init(_ videoPlayer: VideoPlayer) {
            self.videoPlayer = videoPlayer
        }
        
        @MainActor
        func startObserver(uiView: VideoPlayerView) {
            guard observer == nil else { return }
            
            observer = uiView.addPeriodicTimeObserver(forInterval: .init(seconds: 0.25, preferredTimescale: 60)) { [weak self, unowned uiView] time in
                guard let `self` = self else { return }
                
                Task { @MainActor in
                    self.videoPlayer.model.time = time
                }
                self.observerTime = time
                
                self.updateBuffer(uiView: uiView)
            }
        }
        
        func stopObserver(uiView: VideoPlayerView) {
            guard let observer = observer else { return }
            
            uiView.removeTimeObserver(observer)
            
            self.observer = nil
        }
        
        func clean() {
            self.observingURL = nil
            self.observer = nil
            self.observerTime = nil
            self.observerBuffer = nil
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
    
    func convertState() -> VideoState {
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
