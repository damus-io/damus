//
//  OrientationTracker.swift
//  damus
//
//  Created by AI Assistant on 2025-07-30.
//

import SwiftUI

class OrientationTracker: ObservableObject {
    @Published var deviceMajorAxis: CGFloat = 0
    func setDeviceMajorAxis() {
        let bounds = UIScreen.main.bounds
        let height = max(bounds.height, bounds.width)
        let width = min(bounds.height, bounds.width)
        let orientation = UIDevice.current.orientation
        deviceMajorAxis = (orientation == .portrait || orientation == .unknown) ? height : width
    }
}
