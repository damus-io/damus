//
//  NdbUseLock.swift
//  damus
//
//  Created by Daniel D'Aquino on 2025-11-12.
//

import Dispatch
import Synchronization
import Foundation

extension Ndb {
    /// Creates a `sync` mechanism for coordinating usages of ndb (read or write) with the app's ability to close ndb.
    ///
    /// This prevents race condition between threads reading from `ndb` and the app trying to close `ndb`
    ///
    /// Implementation notes:
    /// - This was made as a synchronous mechanism because using `async` solutions (e.g. isolating `Ndb` into an `NdbActor`)
    ///   creates a necessity to change way too much code around the codebase, the interface becomes more cumbersome and difficult to use,
    ///   and might create unnecessary async delays (e.g. it would prevent two tasks from reading Ndb data at once)
    @available(iOS 18.0, *)
    class UseLock: UseLockProtocol {
        private let ndbUserStateCondition = NSCondition()
        private var ndbUserCount: UInt = 0
        private var ndbIsAcquiring: Bool = false
        private let ndbAccessSemaphore: DispatchSemaphore = DispatchSemaphore(value: 0)
        private let ndbIsOpen = Mutex<Bool>(false)
        private static let DEFAULT_TIMEOUT: DispatchTimeInterval = .milliseconds(500)

        func keepNdbOpen<T>(during operation: () throws -> T, maxWaitTimeout: DispatchTimeInterval = DEFAULT_TIMEOUT) throws -> T {
            try self.incrementUserCount(maxTimeout: maxWaitTimeout)
            defer { self.decrementUserCount() }
            return try operation()
        }

        func waitUntilNdbCanClose(thenClose operation: () -> Bool, maxTimeout: DispatchTimeInterval = DEFAULT_TIMEOUT) throws {
            try ndbAccessSemaphore.waitOrThrow(timeout: .now() + maxTimeout)
            ndbIsOpen.withLock { ndbIsOpen in
                ndbIsOpen = operation()
                if ndbIsOpen {
                    ndbAccessSemaphore.signal()
                }
            }
        }

        func markNdbOpen() {
            ndbIsOpen.withLock { ndbIsOpen in
                if !ndbIsOpen {
                    ndbIsOpen = true
                    ndbAccessSemaphore.signal()
                }
            }
        }

        /// Increments user count, using NSCondition so only one thread waits on the semaphore.
        /// Other concurrent threads wait on the condition instead of serializing on the semaphore.
        private func incrementUserCount(maxTimeout: DispatchTimeInterval = .seconds(2)) throws {
            let deadline = Self.timeoutDeadline(for: maxTimeout)

            while true {
                ndbUserStateCondition.lock()

                if ndbUserCount > 0 {
                    ndbUserCount += 1
                    ndbUserStateCondition.unlock()
                    return
                }

                if !ndbIsAcquiring {
                    ndbIsAcquiring = true
                    ndbUserStateCondition.unlock()

                    do {
                        let remaining = deadline.timeIntervalSinceNow
                        guard remaining > 0 else { throw DispatchSemaphore.TimingError.timeout }
                        try ndbAccessSemaphore.waitOrThrow(timeout: .now() + .milliseconds(Int(remaining * 1_000)))
                    } catch {
                        ndbUserStateCondition.lock()
                        ndbIsAcquiring = false
                        ndbUserStateCondition.broadcast()
                        ndbUserStateCondition.unlock()
                        throw error
                    }

                    ndbUserStateCondition.lock()
                    ndbIsAcquiring = false
                    ndbUserCount = 1
                    ndbUserStateCondition.broadcast()
                    ndbUserStateCondition.unlock()
                    return
                }

                let didSignal = ndbUserStateCondition.wait(until: deadline)
                ndbUserStateCondition.unlock()

                guard didSignal else { throw DispatchSemaphore.TimingError.timeout }
            }
        }

        private func decrementUserCount() {
            ndbUserStateCondition.lock()
            defer { ndbUserStateCondition.unlock() }

            ndbUserCount -= 1
            if ndbUserCount == 0 {
                ndbAccessSemaphore.signal()
            }
        }

        private static func timeoutDeadline(for interval: DispatchTimeInterval) -> Date {
            switch interval {
            case .seconds(let s): return Date().addingTimeInterval(TimeInterval(s))
            case .milliseconds(let ms): return Date().addingTimeInterval(TimeInterval(ms) / 1_000.0)
            case .microseconds(let us): return Date().addingTimeInterval(TimeInterval(us) / 1_000_000.0)
            case .nanoseconds(let ns): return Date().addingTimeInterval(TimeInterval(ns) / 1_000_000_000.0)
            case .never: return .distantFuture
            @unknown default: return .distantFuture
            }
        }

        enum LockError: Error {
            case timeout
        }
    }

    /// Fallback for iOS < 18 without Mutex
    class FallbackUseLock: UseLockProtocol {
        private var ndbUserCount: UInt = 0
        private let ndbUserStateCondition = NSCondition()
        private var ndbIsAcquiring: Bool = false
        private let ndbIsOpenLock = NSLock()
        private var ndbIsOpen: Bool = false
        private let ndbAccessSemaphore: DispatchSemaphore = DispatchSemaphore(value: 0)
        private static let DEFAULT_TIMEOUT: DispatchTimeInterval = .milliseconds(500)

        func keepNdbOpen<T>(during operation: () throws -> T, maxWaitTimeout: DispatchTimeInterval = DEFAULT_TIMEOUT) throws -> T {
            try self.incrementUserCount(maxTimeout: maxWaitTimeout)
            defer { self.decrementUserCount() }
            return try operation()
        }

        func waitUntilNdbCanClose(thenClose operation: () -> Bool, maxTimeout: DispatchTimeInterval = DEFAULT_TIMEOUT) throws {
            try ndbAccessSemaphore.waitOrThrow(timeout: .now() + maxTimeout)
            ndbIsOpenLock.lock()
            ndbIsOpen = operation()
            if ndbIsOpen {
                ndbAccessSemaphore.signal()
            }
            ndbIsOpenLock.unlock()
        }

        func markNdbOpen() {
            ndbIsOpenLock.lock()
            if !ndbIsOpen {
                ndbIsOpen = true
                ndbAccessSemaphore.signal()
            }
            ndbIsOpenLock.unlock()
        }

        private func incrementUserCount(maxTimeout: DispatchTimeInterval = .seconds(2)) throws {
            let deadline = Self.timeoutDeadline(for: maxTimeout)

            while true {
                ndbUserStateCondition.lock()

                if ndbUserCount > 0 {
                    ndbUserCount += 1
                    ndbUserStateCondition.unlock()
                    return
                }

                if !ndbIsAcquiring {
                    ndbIsAcquiring = true
                    ndbUserStateCondition.unlock()

                    do {
                        let remaining = deadline.timeIntervalSinceNow
                        guard remaining > 0 else { throw DispatchSemaphore.TimingError.timeout }
                        try ndbAccessSemaphore.waitOrThrow(timeout: .now() + .milliseconds(Int(remaining * 1_000)))
                    } catch {
                        ndbUserStateCondition.lock()
                        ndbIsAcquiring = false
                        ndbUserStateCondition.broadcast()
                        ndbUserStateCondition.unlock()
                        throw error
                    }

                    ndbUserStateCondition.lock()
                    ndbIsAcquiring = false
                    ndbUserCount = 1
                    ndbUserStateCondition.broadcast()
                    ndbUserStateCondition.unlock()
                    return
                }

                let didSignal = ndbUserStateCondition.wait(until: deadline)
                ndbUserStateCondition.unlock()

                guard didSignal else { throw DispatchSemaphore.TimingError.timeout }
            }
        }

        private func decrementUserCount() {
            ndbUserStateCondition.lock()
            defer { ndbUserStateCondition.unlock() }

            ndbUserCount -= 1
            if ndbUserCount == 0 {
                ndbAccessSemaphore.signal()
            }
        }

        private static func timeoutDeadline(for interval: DispatchTimeInterval) -> Date {
            switch interval {
            case .seconds(let s): return Date().addingTimeInterval(TimeInterval(s))
            case .milliseconds(let ms): return Date().addingTimeInterval(TimeInterval(ms) / 1_000.0)
            case .microseconds(let us): return Date().addingTimeInterval(TimeInterval(us) / 1_000_000.0)
            case .nanoseconds(let ns): return Date().addingTimeInterval(TimeInterval(ns) / 1_000_000_000.0)
            case .never: return .distantFuture
            @unknown default: return .distantFuture
            }
        }

        enum LockError: Error {
            case timeout
        }
    }

    protocol UseLockProtocol {
        /// Keeps the ndb open while performing some specified operation.
        ///
        /// **WARNING:** Ensure ndb is open _before_ calling this, otherwise the thread may block for the `maxTimeout` period.
        /// **Implementation note:** NEVER change this to `async`! This is a blocking operation, so we want to minimize the time of the operation
        ///
        /// - Parameter operation: The operation to perform while `ndb` is open. Keep this as short as safely possible!
        /// - Parameter maxTimeout: The maximum amount of time the function will wait for the lock before giving up.
        /// - Returns: The return result for the given operation
        func keepNdbOpen<T>(during operation: () throws -> T, maxWaitTimeout: DispatchTimeInterval) throws -> T

        /// Waits for ndb to be able to close, then closes it.
        ///
        /// - Parameter operation: The operation to close. Must return the final boolean value indicating if ndb was closed in the end
        ///
        /// Implementation note: NEVER change this to `async`! This is a blocking operation, so we want to minimize the time of the operation
        func waitUntilNdbCanClose(thenClose operation: () -> Bool, maxTimeout: DispatchTimeInterval) throws

        /// Marks `ndb` as open to allow other users to use it. Do not call this more than once
        func markNdbOpen()
    }

    static func initLock() -> UseLockProtocol {
        if #available(iOS 18.0, *) {
            return UseLock()
        } else {
            return FallbackUseLock()
        }
    }
}

fileprivate extension DispatchSemaphore {
    func waitOrThrow(timeout: DispatchTime) throws(TimingError) {
        let result = self.wait(timeout: timeout)
        switch result {
        case .success: return
        case .timedOut: throw .timeout
        }
    }

    enum TimingError: Error {
        case timeout
    }
}
