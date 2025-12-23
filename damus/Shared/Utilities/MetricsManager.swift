//
//  MetricsManager.swift
//  damus
//
//  Created for 0xdead10cc crash diagnostics
//

import Foundation
import MetricKit

/// Manages MetricKit integration for collecting app exit diagnostics.
/// Helps identify whether 0xdead10cc crashes are caused by:
/// - Background task assertion timeouts
/// - File locks held during suspend (LMDB/nostrdb)
class MetricsManager: NSObject, MXMetricManagerSubscriber {
    static let shared = MetricsManager()

    private override init() {
        super.init()
    }

    /// Call this from AppDelegate.didFinishLaunching to start collecting metrics
    func start() {
        MXMetricManager.shared.add(self)
        Log.info("MetricsManager: Started collecting MetricKit data", for: .app_lifecycle)
    }

    /// Called by MetricKit when daily metric payloads are available (iOS 13+)
    func didReceive(_ payloads: [MXMetricPayload]) {
        for payload in payloads {
            processMetricPayload(payload)
        }
    }

    /// Called by MetricKit when diagnostic payloads are available (iOS 14+)
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        for payload in payloads {
            processDiagnosticPayload(payload)
        }
    }

    // MARK: - Metric Processing

    private func processMetricPayload(_ payload: MXMetricPayload) {
        guard let appExitMetric = payload.applicationExitMetrics else {
            return
        }

        let bg = appExitMetric.backgroundExitData
        let fg = appExitMetric.foregroundExitData

        // Log background exit reasons - these are what we care about for 0xdead10cc
        Log.info("MetricKit AppExit [Background]: normal=%d, abnormal=%d, watchdog=%d, taskTimeout=%d, fileLock=%d, memory=%d, suspended=%d",
                 for: .app_lifecycle,
                 bg.cumulativeNormalAppExitCount,
                 bg.cumulativeAbnormalExitCount,
                 bg.cumulativeAppWatchdogExitCount,
                 bg.cumulativeBackgroundTaskAssertionTimeoutExitCount,  // Background task didn't end in time
                 bg.cumulativeSuspendedWithLockedFileExitCount,         // File lock held during suspend (LMDB?)
                 bg.cumulativeMemoryPressureExitCount,
                 bg.cumulativeSuspendedWithLockedFileExitCount)

        // Log foreground exits for completeness
        Log.info("MetricKit AppExit [Foreground]: normal=%d, abnormal=%d, watchdog=%d",
                 for: .app_lifecycle,
                 fg.cumulativeNormalAppExitCount,
                 fg.cumulativeAbnormalExitCount,
                 fg.cumulativeAppWatchdogExitCount)

        // Key metrics for 0xdead10cc investigation
        let taskTimeouts = bg.cumulativeBackgroundTaskAssertionTimeoutExitCount
        let fileLockExits = bg.cumulativeSuspendedWithLockedFileExitCount

        if taskTimeouts > 0 || fileLockExits > 0 {
            Log.error("MetricKit: DETECTED SUSPENSION ISSUES - taskTimeouts=%d, fileLockExits=%d",
                     for: .app_lifecycle,
                     taskTimeouts,
                     fileLockExits)
        }
    }

    private func processDiagnosticPayload(_ payload: MXDiagnosticPayload) {
        // Log crash diagnostics
        if let crashDiagnostics = payload.crashDiagnostics {
            for crash in crashDiagnostics {
                Log.error("MetricKit Crash: terminationReason=%@, signal=%@",
                         for: .app_lifecycle,
                         crash.terminationReason ?? "unknown",
                         crash.signal?.description ?? "unknown")
            }
        }

        // Log hang diagnostics
        if let hangDiagnostics = payload.hangDiagnostics {
            Log.info("MetricKit: Received %d hang diagnostics", for: .app_lifecycle, hangDiagnostics.count)
        }

        // Log CPU exceptions (might indicate heavy work during background)
        if let cpuDiagnostics = payload.cpuExceptionDiagnostics {
            Log.info("MetricKit: Received %d CPU exception diagnostics", for: .app_lifecycle, cpuDiagnostics.count)
        }
    }

    deinit {
        MXMetricManager.shared.remove(self)
    }
}
