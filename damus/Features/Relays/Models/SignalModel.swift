//
//  SignalModel.swift
//  damus
//
//  Created by William Casarin on 2022-05-24.
//

import Foundation
import Network

class SignalModel: ObservableObject {
    @Published var signal: Int
    @Published var max_signal: Int
    @Published var isNetworkReachable: Bool
    
    private var monitor: NWPathMonitor?
    private let monitorQueue = DispatchQueue(label: "io.damus.connectivity.signal")
    
    init(signal: Int = 0, max_signal: Int = 0, isNetworkReachable: Bool = true) {
        self.signal = signal
        self.max_signal = max_signal
        self.isNetworkReachable = isNetworkReachable
        startMonitor()
    }
    
    deinit {
        monitor?.cancel()
    }
    
    var isOffline: Bool {
        (!isNetworkReachable) || (max_signal > 0 && signal == 0)
    }
    
    private func startMonitor() {
        let monitor = NWPathMonitor()
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
