//
//  DamusVideoCoordinator.swift
//  damus
//
//  Created by Bryan Montz on 9/3/23.
//

import Combine
import Foundation
import SwiftUI
import AVFoundation

/// DamusVideoCoordinator is responsible for coordinating the various video players throughout the app, and providing a nicely orchestrated experience.
/// The goals of this object are to:
/// - ensure some video playing states (such as mute state and current time) are consistent across different video player view instances of the same video
/// - ensure only one video is playing at a time
/// - Provide global video playback controls to control the currently playing video
///
/// This is used as a singleton object (one global object per `DamusState`), which gets passed around to video players, which can then interact with the coordinator to ensure an app-wide coherent experience
///
/// A good analogy here is that video players and their models/states are like individual cars and their drivers, and this coordinator is like a traffic control person + traffic lights that ensures cars don't crash each other.
///
/// `@MainActor` ensures all mutable state (request stacks, focused video, player cache) is
/// accessed exclusively on the main thread. All callers are SwiftUI views which already run
/// on main. The `DispatchQueue.main.async` calls inside `select_focused_video` and
/// `invokeOnMain` are retained to defer work to the next run loop iteration, avoiding
/// re-entrancy during SwiftUI view update cycles.
@MainActor
final class DamusVideoCoordinator: ObservableObject {
    // MARK: - States
    
    // MARK: State and information about each video
    private var players: [URL: DamusVideoPlayer] = [:]
    
    // MARK: Main stage requests from player views
    // The stacks of video player views that have marked themselves as visible on the user screen.
    //
    // Because our visibility tracker cannot tell if a player is obscured by a view in front of it,
    // we need to implement two stacks representing the different view layers:
    // - Normal layer: For timelines, threads, etc
    // - Full screen layer: For full screen views
    
    private var normal_layer_main_stage_requests: [MainStageRequest] = []
    private var full_screen_layer_stage_requests: [MainStageRequest] = []
    
    // MARK: Coordinator state
    // Members representing the state of the coordinator itself
    
    /// Tracks the requestor that currently has render ownership for fallback surface management
    private var focused_requestor_id: UUID?

    private var full_screen_mode: Bool = false {
        didSet {
            self.select_focused_video()
        }
    }
    
    /// The video currently in focus
    /// This can only be chosen by the coordinator. To get a video in focus, use one of the instance methods that provide an interface for focus control.
    @Published private(set) var focused_video: DamusVideoPlayer? {
        didSet {
            oldValue?.pause()
            focused_video?.play()
            Log.info("VIDEO_COORDINATOR: %s paused, playing %s", for: .video_coordination, oldValue?.url.absoluteString ?? "no video", focused_video?.url.absoluteString ?? "no video")
        }
    }
    
    // MARK: - Interface to set and fetch information about each different video

    
    func get_player(for url: URL) -> DamusVideoPlayer {
        if let player = self.players[url] {
            return player
        }
        let player = DamusVideoPlayer(url: url)
        self.players[url] = player
        return player
    }

    
    // MARK: - Interface for video players to come to the foreground
    // This portion provides an interface for video players to signal their visibility changes,
    // and implements some coordination logic to choose which video to play and pause at a given time.
    
    func request_main_stage(_ request: MainStageRequest) {
        Log.info("VIDEO_COORDINATOR: %s requested main stage", for: .video_coordination, request.requestor_id.uuidString)
        switch request.layer_context {
            case .normal_layer:
                if normal_layer_main_stage_requests.first(where: { $0.requestor_id == request.requestor_id }) != nil { return } // Entry exists already
                normal_layer_main_stage_requests.append(request)
            case .full_screen_layer:
                if full_screen_layer_stage_requests.first(where: { $0.requestor_id == request.requestor_id }) != nil { return } // Entry exists already
                full_screen_layer_stage_requests.append(request)
        }
        self.select_focused_video()
    }
    
    func give_up_main_stage(request_id: UUID) {
        Log.info("VIDEO_COORDINATOR: %s gave up the main stage", for: .video_coordination, request_id.uuidString)
        // Fire revoke before removal so the requestor can clean up render ownership
        let allRequests = normal_layer_main_stage_requests + full_screen_layer_stage_requests
        if let request = allRequests.first(where: { $0.requestor_id == request_id }) {
            invokeOnMain(request.main_stage_revoked)
        }
        if focused_requestor_id == request_id {
            focused_requestor_id = nil
        }
        normal_layer_main_stage_requests.removeAll(where: { $0.requestor_id == request_id })
        full_screen_layer_stage_requests.removeAll(where: { $0.requestor_id == request_id })
        self.select_focused_video()
    }
    
    // MARK: - Additional interface to help with video coordination
    
    func set_full_screen_mode(_ is_full_screen: Bool) {
        full_screen_mode = is_full_screen
    }
    
    // MARK: - Internal video coordination logic
    
    /// Ensures UI-affecting callbacks run asynchronously on the main thread.
    /// Always dispatches async to avoid re-entrancy when mutating @State
    /// during a SwiftUI view update cycle.
    private func invokeOnMain(_ callback: (() -> Void)?) {
        guard let callback else { return }
        DispatchQueue.main.async(execute: callback)
    }

    private func select_focused_video() {
        // This function may be called during a SwiftUI view update,
        // so schedule this change for the next render pass to ensure state immutability/stability within a single render pass
        DispatchQueue.main.async { [weak self] in   // [weak self] to safeguard in cases this object is deallocated by the time we execute this task
            guard let self else { return }
            // The focused video will always be the last one that was inserted — similar to a LIFO stack
            // The reason is that:
            // - both a LIFO stack and a FIFO queue are decent at selecting videos when scrolling on the Y axis (timeline),
            // - The LIFO stack is better at selecting videos when navigating on the Z axis (e.g. opening and closing full screen covers or sheets), since those sheets operate like a stack as well
            let winning_request = self.full_screen_mode ? self.full_screen_layer_stage_requests.last : self.normal_layer_main_stage_requests.last

            // Notify old requestor it lost focus (if different from new winner)
            if let oldId = self.focused_requestor_id, oldId != winning_request?.requestor_id {
                let allRequests = self.normal_layer_main_stage_requests + self.full_screen_layer_stage_requests
                self.invokeOnMain(allRequests.first(where: { $0.requestor_id == oldId })?.main_stage_revoked)
            }

            self.focused_video = winning_request?.player
            self.focused_requestor_id = winning_request?.requestor_id
            self.invokeOnMain(winning_request?.main_stage_granted)
        }
        Log.info("VIDEO_COORDINATOR: fullscreen layer main stage request stack: %s", for: .video_coordination, full_screen_layer_stage_requests.map({ $0.requestor_id.uuidString }).debugDescription)
        Log.info("VIDEO_COORDINATOR: normal layer main stage request stack: %s", for: .video_coordination, normal_layer_main_stage_requests.map({ $0.requestor_id.uuidString }).debugDescription)
        Log.info("VIDEO_COORDINATOR: full_screen_mode: %s", for: .video_coordination, String(describing: self.full_screen_mode))
    }
    
    // MARK: - Helper structures
    
    struct MainStageRequest {
        var requestor_id: UUID
        var layer_context: ViewLayerContext
        var player: DamusVideoPlayer
        /// Called when this requestor is granted focus and should begin rendering.
        var main_stage_granted: (() -> Void)?
        /// Called when this requestor loses focus and should stop rendering the fallback surface.
        var main_stage_revoked: (() -> Void)?
    }
}
