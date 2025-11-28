//
//  SignalModelTests.swift
//  damusTests
//
//  Created by OpenAI Codex on 2025-01-04.
//

import XCTest
import Network
@testable import damus

final class SignalModelTests: XCTestCase {
    
    private func makeSignalModel(signal: Int = 0, maxSignal: Int = 0, reachable: Bool = true) -> SignalModel {
        SignalModel(signal: signal,
                    max_signal: maxSignal,
                    isNetworkReachable: reachable,
                    monitorFactory: { MockPathMonitor() })
    }
    
    func testOfflineWhenAllRelaysDisconnected() {
        let model = makeSignalModel(signal: 0, maxSignal: 3, reachable: true)
        XCTAssertTrue(model.isOffline)
    }
    
    func testOnlineWhenRelayConnected() {
        let model = makeSignalModel(signal: 1, maxSignal: 3, reachable: true)
        XCTAssertFalse(model.isOffline)
    }
    
    func testNetworkOutageForcesOfflineRegardlessOfRelays() {
        let model = makeSignalModel(signal: 3, maxSignal: 3, reachable: false)
        XCTAssertTrue(model.isOffline)
    }
    
    func testNoRelaysConfiguredCountsAsOffline() {
        let model = makeSignalModel(signal: 0, maxSignal: 0, reachable: true)
        XCTAssertTrue(model.isOffline)
    }
}

private final class MockPathMonitor: NetworkPathMonitoring {
    var pathUpdateHandler: ((NWPath) -> Void)?
    
    func start(queue: DispatchQueue) {
        // Intentionally left blank; tests set reachability directly.
    }
    
    func cancel() {}
}
