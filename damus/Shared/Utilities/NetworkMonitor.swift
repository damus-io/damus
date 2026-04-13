//
//  NetworkMonitor.swift
//  damus
//
//  Created for issue #919: Low data / cellular mode.
//

import Foundation
import Network

/// A singleton class that monitors network connectivity state.
///
/// `NetworkMonitor` uses Apple's `NWPathMonitor` to detect when the device is
/// operating under constrained network conditions (iOS Low Data Mode) or on
/// expensive connections (cellular networks).
///
/// ## Usage
/// ```swift
/// if NetworkMonitor.shared.isLowDataMode {
///     // Skip loading media
/// }
/// ```
///
/// ## Thread Safety
/// The `isLowDataMode` property is always updated on the main thread,
/// making it safe to use directly in SwiftUI views.
///
/// - SeeAlso: `UserSettingsStore.low_data_mode` for the user-controlled toggle.
class NetworkMonitor: ObservableObject {
    
    /// The shared singleton instance of `NetworkMonitor`.
    ///
    /// Access this property to check the current network state.
    static let shared = NetworkMonitor()
    
    /// The `NWPathMonitor` instance used to observe network changes.
    private let monitor = NWPathMonitor()
    
    /// The dispatch queue on which network updates are received.
    private let queue = DispatchQueue(label: "com.damus.networkmonitor")
    
    /// Indicates whether the device is currently in a low-data network state.
    ///
    /// This property returns `true` when:
    /// - iOS Low Data Mode is enabled by the user (`path.isConstrained`)
    /// - The device is on a cellular connection (`path.isExpensive`)
    ///
    /// Use this property to conditionally disable media auto-loading.
    @Published private(set) var isLowDataMode: Bool = false
    
    /// Initializes the `NetworkMonitor` and starts observing network changes.
    ///
    /// This initializer is private to enforce the singleton pattern.
    /// Use `NetworkMonitor.shared` to access the instance.
    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                self?.isLowDataMode = path.isConstrained || path.isExpensive
            }
        }
        monitor.start(queue: queue)
    }
    
    /// Stops monitoring network changes when the instance is deallocated.
    deinit {
        monitor.cancel()
    }
}
