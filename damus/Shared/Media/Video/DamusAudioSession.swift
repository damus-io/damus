//
//  DamusAudioSession.swift
//  damus
//
//  Created for KSPlayer fallback integration.
//

import AVFoundation

/// Centralized audio session configuration for Damus.
/// Used by both normal app startup and post-KSMEPlayer-init restoration.
enum DamusAudioSession {
    /// Restores Damus's preferred audio session: playback with mix-with-others.
    static func restore() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: .mixWithOthers)
        } catch {
            Log.error("[debug-video] DamusAudioSession: Failed to restore audio session: %s", for: .video_coordination, error.localizedDescription)
        }
    }
}
