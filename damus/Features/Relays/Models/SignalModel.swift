//
//  SignalModel.swift
//  damus
//
//  Created by William Casarin on 2022-05-24.
//

import Foundation
import Network

protocol NetworkPathMonitoring: AnyObject {
    var pathUpdateHandler: (@Sendable (NWPath) -> Void)? { get set }
    func start(queue: DispatchQueue)
    func cancel()
}

extension NWPathMonitor: NetworkPathMonitoring {}

class SignalModel: ObservableObject {
    @Published var signal: Int
    @Published var max_signal: Int
    @Published var isNetworkReachable: Bool
    
    private var monitor: NetworkPathMonitoring?
    private let monitorQueue = DispatchQueue(label: "io.damus.connectivity.signal")
    private let monitorFactory: () -> NetworkPathMonitoring
    
    init(signal: Int = 0, max_signal: Int = 0, isNetworkReachable: Bool = true, monitorFactory: @escaping () -> NetworkPathMonitoring = { NWPathMonitor() }) {
        self.signal = signal
        self.max_signal = max_signal
        self.isNetworkReachable = isNetworkReachable
        self.monitorFactory = monitorFactory
        startMonitor()
    }
    
    deinit {
        monitor?.cancel()
    }
    
    var isOffline: Bool {
        if !isNetworkReachable {
            return true
        }
        guard max_signal > 0 else {
            // Relay counts are unknown until the relay list loads; avoid flashing offline until we have real data.
            return false
        }
        return signal == 0
    }
    
    private func startMonitor() {
        let monitor = monitorFactory()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            DispatchQueue.main.async {
                self.isNetworkReachable = path.status == .satisfied
            }
        }
        monitor.start(queue: monitorQueue)
    }
}
