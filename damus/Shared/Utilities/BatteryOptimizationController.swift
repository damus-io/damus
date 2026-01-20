//
//  BatteryOptimizationController.swift
//  damus
//
//  Created by OpenAI Codex on 2025-04-02.
//

import Combine
import Foundation
import UIKit

final class BatteryOptimizationController: ObservableObject {
    enum PowerMode: Comparable {
        case performance
        case balanced
        case powerSaver
        case ultraLow
        
        var priority: Int {
            switch self {
            case .performance: return 3
            case .balanced: return 2
            case .powerSaver: return 1
            case .ultraLow: return 0
            }
        }
        
        static func < (lhs: PowerMode, rhs: PowerMode) -> Bool {
            lhs.priority < rhs.priority
        }
    }
    
    struct Configuration {
        let mode: PowerMode
        let streamPreference: StreamPreference
        let maxConcurrentSubscriptions: Int
        let scanRestInterval: TimeInterval
        let eoseTimeout: TimeInterval
    }
    
    enum StreamPreference {
        case ndbFirst(optimizeNetworkFilter: Bool)
        case ndbAndNetworkParallel(optimizeNetworkFilter: Bool)
        case ndbOnly
    }
    
    @Published private(set) var configuration: Configuration
    
    private let device: UIDevice
    private let notificationCenter: NotificationCenter
    private var notificationTokens: [NSObjectProtocol] = []
    private var isBackgrounded = false
    
    init(device: UIDevice, notificationCenter: NotificationCenter = .default) {
        self.device = device
        self.notificationCenter = notificationCenter
        self.configuration = Self.configuration(for: .balanced)
        device.isBatteryMonitoringEnabled = true
        self.observeBatteryChanges()
        self.updateConfiguration()
    }
    
    deinit {
        notificationTokens.forEach(notificationCenter.removeObserver)
    }
    
    func setAppBackgrounded(_ backgrounded: Bool) {
        guard backgrounded != isBackgrounded else { return }
        isBackgrounded = backgrounded
        updateConfiguration()
    }
    
    private func observeBatteryChanges() {
        let handlers: [NSNotification.Name] = [
            UIDevice.batteryLevelDidChangeNotification,
            UIDevice.batteryStateDidChangeNotification
        ]
        
        for name in handlers {
            let token = notificationCenter.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                self?.updateConfiguration()
            }
            notificationTokens.append(token)
        }
    }
    
    private func updateConfiguration() {
        let level = device.batteryLevel
        let isCharging = device.batteryState == .charging || device.batteryState == .full
        let rawMode = Self.powerMode(for: level, isCharging: isCharging)
        let effectiveMode = applyBackgroundPolicy(rawMode: rawMode)
        configuration = Self.configuration(for: effectiveMode)
    }
    
    private func applyBackgroundPolicy(rawMode: PowerMode) -> PowerMode {
        guard isBackgrounded else { return rawMode }
        if rawMode == .ultraLow {
            return .ultraLow
        }
        return .powerSaver
    }
    
    private static func powerMode(for batteryLevel: Float, isCharging: Bool) -> PowerMode {
        guard batteryLevel >= 0 else {
            return .balanced
        }
        if isCharging || batteryLevel >= 0.6 {
            return .performance
        }
        if batteryLevel >= 0.3 {
            return .balanced
        }
        if batteryLevel >= 0.1 {
            return .powerSaver
        }
        return .ultraLow
    }
    
    private static func configuration(for mode: PowerMode) -> Configuration {
        switch mode {
        case .performance:
            return Configuration(
                mode: mode,
                streamPreference: .ndbAndNetworkParallel(optimizeNetworkFilter: false),
                maxConcurrentSubscriptions: 18,
                scanRestInterval: 0.0,
                eoseTimeout: 5.0
            )
        case .balanced:
            return Configuration(
                mode: mode,
                streamPreference: .ndbAndNetworkParallel(optimizeNetworkFilter: true),
                maxConcurrentSubscriptions: 14,
                scanRestInterval: 0.5,
                eoseTimeout: 6.0
            )
        case .powerSaver:
            return Configuration(
                mode: mode,
                streamPreference: .ndbFirst(optimizeNetworkFilter: true),
                maxConcurrentSubscriptions: 10,
                scanRestInterval: 2.0,
                eoseTimeout: 8.0
            )
        case .ultraLow:
            return Configuration(
                mode: mode,
                streamPreference: .ndbOnly,
                maxConcurrentSubscriptions: 6,
                scanRestInterval: 5.0,
                eoseTimeout: 12.0
            )
        }
    }
}
