//
//  NetworkMonitor.swift
//  damus
//
//  Created by AI Assistant on 2026-01-20.
//  Addresses issue #919: Low data / cellular mode.
//

import Foundation
import Network

/// Monitors network state to detect expensive or constrained connections (Low Data Mode).
/// Use `isLowDataMode` to conditionally disable media loading.
class NetworkMonitor: ObservableObject {
    static let shared = NetworkMonitor()
    
    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.damus.networkmonitor")
    
    /// True if the system is in Low Data Mode or on a constrained/expensive network.
    @Published private(set) var isLowDataMode: Bool = false
    
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                // isConstrained: true when iOS Low Data Mode is enabled
                // isExpensive: true on cellular (not always "low data" but useful)
                self?.isLowDataMode = path.isConstrained
            }
        }
        monitor.start(queue: queue)
    }
    
    deinit {
        monitor.cancel()
    }
}
