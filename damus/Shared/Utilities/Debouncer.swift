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
    private let lock = NSLock()
    private var interval: TimeInterval

    init(interval: TimeInterval) {
        self.interval = interval
    }

    func debounce(action: @escaping () -> Void) {
        lock.lock()
        // Cancel the previous work item if it hasn't yet executed
        workItem?.cancel()

        // Create a new work item with a delay
        let item = DispatchWorkItem { [weak self] in
            action()
            self?.lock.lock()
            self?.workItem = nil
            self?.lock.unlock()
        }
        workItem = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + interval, execute: item)
    }

    func debounce_immediate(action: @escaping () -> Void) {
        lock.lock()
        guard self.workItem == nil else {
            lock.unlock()
            return
        }

        let item = DispatchWorkItem(block: { [weak self] in
            self?.lock.lock()
            self?.workItem = nil
            self?.lock.unlock()
        })
        self.workItem = item
        lock.unlock()

        action()
        queue.asyncAfter(deadline: .now() + interval, execute: item)
    }

    func debounce_once(action: @escaping () -> Void) {
        lock.lock()
        guard self.workItem == nil else {
            lock.unlock()
            return
        }

        let item = DispatchWorkItem(block: { [weak self] in
            self?.lock.lock()
            self?.workItem = nil
            self?.lock.unlock()
            action()
        })
        self.workItem = item
        lock.unlock()

        queue.asyncAfter(deadline: .now() + interval, execute: item)
    }
}
