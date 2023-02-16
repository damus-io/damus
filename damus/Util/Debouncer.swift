//
//  Debouncer.swift
//  damus
//
//  Created by William Casarin on 2023-02-15.
//

import Foundation

class Debouncer {
    private let queue = DispatchQueue.main
    private var workItem: DispatchWorkItem?
    private var interval: TimeInterval

    init(interval: TimeInterval) {
        self.interval = interval
    }

    func debounce(action: @escaping () -> Void) {
        // Cancel the previous work item if it hasn't yet executed
        workItem?.cancel()

        // Create a new work item with a delay
        workItem = DispatchWorkItem { action() }
        queue.asyncAfter(deadline: .now() + interval, execute: workItem!)
    }
}
