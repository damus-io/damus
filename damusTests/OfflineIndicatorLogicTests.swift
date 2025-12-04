//
//  OfflineIndicatorLogicTests.swift
//  damusTests
//
//  Created by OpenAI Codex on 2025-01-04.
//

import XCTest
import Network
@testable import damus

final class OfflineIndicatorLogicTests: XCTestCase {
    
    private func makeOfflineSignal(isOffline: Bool) -> SignalModel {
        let reachable = !isOffline
        let signalCount = isOffline ? 0 : 1
        let maxSignal = 1
        let model = SignalModel(signal: signalCount,
                                max_signal: maxSignal,
                                isNetworkReachable: reachable,
                                monitorFactory: { MockPathMonitor() })
        if isOffline {
            model.signal = 0
            model.max_signal = 1
            model.isNetworkReachable = false
        }
        return model
    }
    
    func testIndicatorHiddenForNonHomeTimeline() {
        let result = shouldShowFloatingOfflineIndicator(timeline: .notifications,
                                                        signal: makeOfflineSignal(isOffline: true),
                                                        headerOffset: -50)
        XCTAssertFalse(result)
    }
    
    func testIndicatorVisibleWhenScrolledAndOffline() {
        let result = shouldShowFloatingOfflineIndicator(timeline: .home,
                                                        signal: makeOfflineSignal(isOffline: true),
                                                        headerOffset: -40)
        XCTAssertTrue(result)
    }
    
    func testIndicatorHiddenWhenHeaderVisible() {
        let result = shouldShowFloatingOfflineIndicator(timeline: .home,
                                                        signal: makeOfflineSignal(isOffline: true),
                                                        headerOffset: -10)
        XCTAssertFalse(result)
    }
    
    func testIndicatorHiddenWhenOnline() {
        let result = shouldShowFloatingOfflineIndicator(timeline: .home,
                                                        signal: makeOfflineSignal(isOffline: false),
                                                        headerOffset: -40)
        XCTAssertFalse(result)
    }
}

private final class MockPathMonitor: NetworkPathMonitoring {
    var pathUpdateHandler: ((NWPath) -> Void)?
    
    func start(queue: DispatchQueue) {}
    func cancel() {}
}
