//
//  GroupedModeQueueManager.swift
//  damus
//
//  Created by alltheseas on 2025-12-07.
//

import Foundation

/// Manages EventHolder queue state for grouped mode transitions.
/// Extracted from View for testability.
struct GroupedModeQueueManager {
    /// Flushes queued events and disables queueing so grouped view sees all events.
    @MainActor
    static func flush(source: EventHolder) {
        source.flush()
        source.set_should_queue(false)
    }
}
