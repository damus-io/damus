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
        /// Condition for coordinating user-count changes and acquisition flow.
        private let ndbUserStateCondition = NSCondition()
        /// Number of functions using the `ndb` object (for reading or writing data)
        private var ndbUserCount: UInt = 0
        /// Tracks whether a "first user" is currently acquiring the semaphore.
        private var ndbIsAcquiring: Bool = false
        /// Semaphore for general access to `ndb`. A closing task requires exclusive access. Users of `ndb` (read/write tasks) share the access
        private let ndbAccessSemaphore: DispatchSemaphore = DispatchSemaphore(value: 0)
        private let ndbIsOpen = Mutex<Bool>(false)
        /// How long a thread can block before throwing an error
        private static let DEFAULT_TIMEOUT: DispatchTimeInterval = .milliseconds(500)

        /// Keeps the ndb open while performing some specified operation.
        ///
        /// **WARNING:** Ensure ndb is open _before_ calling this, otherwise the thread may block for the `maxTimeout` period.
        /// **Implementation note:** NEVER change this to `async`! This is a blocking operation, so we want to minimize the time of the operation
        ///
        /// - Parameter operation: The operation to perform while `ndb` is open. Keep this as short as safely possible!
        /// - Parameter maxTimeout: The maximum amount of time the function will wait for the lock before giving up.
        /// - Returns: The return result for the given operation
        func keepNdbOpen<T>(during operation: () throws -> T, maxWaitTimeout: DispatchTimeInterval = DEFAULT_TIMEOUT) throws -> T {
            try self.incrementUserCount(maxTimeout: maxWaitTimeout)
            defer { self.decrementUserCount() } // Use defer to guarantee this will always be called no matter the outcome of the function
            return try operation()
        }

        /// Waits for ndb to be able to close, then closes it.
        ///
        /// - Parameter operation: The operation to close. Must return the final boolean value indicating if ndb was closed in the end
        ///
        /// Implementation note: NEVER change this to `async`! This is a blocking operation, so we want to minimize the time of the operation
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

        /// Increments the user count, waiting for the semaphore if this is the first user.
        ///
        /// This method uses an NSCondition to coordinate the "first user acquiring" state.
        /// Only one thread will wait on the semaphore; other concurrent threads wait on the
        /// condition and are woken when the first user successfully acquires access.
        /// This prevents multiple threads from serializing on the semaphore.
        ///
        /// - Parameter maxTimeout: Maximum time to wait for access.
        /// - Throws: `DispatchSemaphore.TimingError.timeout` if the wait times out.
        private func incrementUserCount(maxTimeout: DispatchTimeInterval = .seconds(2)) throws {
            // Compute deadline once at entry to avoid exceeding maxTimeout across retries
            let deadline = Self.timeoutDeadline(for: maxTimeout)

            while true {
                ndbUserStateCondition.lock()

                // If there are already users, just increment and return
                if ndbUserCount > 0 {
                    ndbUserCount += 1
                    ndbUserStateCondition.unlock()
                    return
                }

                // No users yet - check if someone is already acquiring
                if !ndbIsAcquiring {
                    // We are the first - mark as acquiring and go get the semaphore
                    ndbIsAcquiring = true
                    ndbUserStateCondition.unlock()

                    // Wait for semaphore WITHOUT holding the lock to prevent thread starvation
                    // Use do/catch to ensure ndbIsAcquiring is cleared even if wait throws
                    do {
                        let remaining = deadline.timeIntervalSinceNow
                        if remaining <= 0 {
                            throw DispatchSemaphore.TimingError.timeout
                        }
                        try ndbAccessSemaphore.waitOrThrow(timeout: .now() + .milliseconds(Int(remaining * 1_000)))
                    } catch {
                        // Clear acquiring flag and wake waiting threads before re-throwing
                        ndbUserStateCondition.lock()
                        ndbIsAcquiring = false
                        ndbUserStateCondition.broadcast()
                        ndbUserStateCondition.unlock()
                        throw error
                    }

                    // Successfully acquired - update state and wake waiting threads
                    ndbUserStateCondition.lock()
                    ndbIsAcquiring = false
                    ndbUserCount = 1
                    ndbUserStateCondition.broadcast()
                    ndbUserStateCondition.unlock()
                    return
                }

                // Someone else is acquiring - wait for them to finish
                let didSignal = ndbUserStateCondition.wait(until: deadline)
                ndbUserStateCondition.unlock()

                if !didSignal {
                    throw DispatchSemaphore.TimingError.timeout
                }
                // Loop back to check state again
            }
        }

        /// Decrements the active user count and signals when database can close.
        ///
        /// Acquires `ndbUserStateCondition` to safely decrement `ndbUserCount`.
        /// When count reaches zero, signals `ndbAccessSemaphore` to unblock
        /// any pending close operation. Thread-safe via internal locking.
        private func decrementUserCount() {
            ndbUserStateCondition.lock()
            defer { ndbUserStateCondition.unlock() }

            ndbUserCount -= 1
            // Signal that ndb can close if we have zero users using ndb
            if ndbUserCount == 0 {
                ndbAccessSemaphore.signal()
            }
        }

        /// Converts a DispatchTimeInterval into a Date deadline for NSCondition waits.
        private static func timeoutDeadline(for interval: DispatchTimeInterval) -> Date {
            switch interval {
            case .seconds(let seconds):
                return Date().addingTimeInterval(TimeInterval(seconds))
            case .milliseconds(let milliseconds):
                return Date().addingTimeInterval(TimeInterval(milliseconds) / 1_000.0)
            case .microseconds(let microseconds):
                return Date().addingTimeInterval(TimeInterval(microseconds) / 1_000_000.0)
            case .nanoseconds(let nanoseconds):
                return Date().addingTimeInterval(TimeInterval(nanoseconds) / 1_000_000_000.0)
            case .never:
                return .distantFuture
            @unknown default:
                return .distantFuture
            }
        }

        enum LockError: Error {
            case timeout
        }
    }

    /// A fallback implementation for `UseLock` that works in iOS older than iOS 18, with reduced syncing mechanisms
    class FallbackUseLock: UseLockProtocol {
        /// Number of functions using the `ndb` object (for reading or writing data)
        private var ndbUserCount: UInt = 0
        /// Condition for coordinating user-count changes and acquisition flow.
        private let ndbUserStateCondition = NSCondition()
        /// Tracks whether a "first user" is currently acquiring the semaphore.
        private var ndbIsAcquiring: Bool = false
        /// Lock for protecting access to `ndbIsOpen`
        private let ndbIsOpenLock = NSLock()
        private var ndbIsOpen: Bool = false
        /// Semaphore for general access to `ndb`. A closing task requires exclusive access. Users of `ndb` (read/write tasks) share the access
        private let ndbAccessSemaphore: DispatchSemaphore = DispatchSemaphore(value: 0)
        /// How long a thread can block before throwing an error
        private static let DEFAULT_TIMEOUT: DispatchTimeInterval = .milliseconds(500)

        /// Keeps the ndb open while performing some specified operation.
        ///
        /// **WARNING:** Ensure ndb is open _before_ calling this, otherwise the thread may block for the `maxTimeout` period.
        /// **Implementation note:** NEVER change this to `async`! This is a blocking operation, so we want to minimize the time of the operation
        ///
        /// - Parameter operation: The operation to perform while `ndb` is open. Keep this as short as safely possible!
        /// - Parameter maxTimeout: The maximum amount of time the function will wait for the lock before giving up.
        /// - Returns: The return result for the given operation
        func keepNdbOpen<T>(during operation: () throws -> T, maxWaitTimeout: DispatchTimeInterval = DEFAULT_TIMEOUT) throws -> T {
            try self.incrementUserCount(maxTimeout: maxWaitTimeout)
            defer { self.decrementUserCount() } // Use defer to guarantee this will always be called no matter the outcome of the function
            return try operation()
        }

        /// Waits for ndb to be able to close, then closes it.
        ///
        /// - Parameter operation: The operation to close. Must return the final boolean value indicating if ndb was closed in the end
        ///
        /// Implementation note: NEVER change this to `async`! This is a blocking operation, so we want to minimize the time of the operation
        func waitUntilNdbCanClose(thenClose operation: () -> Bool, maxTimeout: DispatchTimeInterval = DEFAULT_TIMEOUT) throws {
            try ndbAccessSemaphore.waitOrThrow(timeout: .now() + maxTimeout)
            ndbIsOpenLock.lock()
            ndbIsOpen = operation()
            if ndbIsOpen {
                ndbAccessSemaphore.signal()
            }
            ndbIsOpenLock.unlock()
        }

        /// Marks `ndb` as open to allow other users to use it. Do not call this more than once
        func markNdbOpen() {
            ndbIsOpenLock.lock()
            if !ndbIsOpen {
                ndbIsOpen = true
                ndbAccessSemaphore.signal()
            }
            ndbIsOpenLock.unlock()
        }

        /// Increments the user count, waiting for the semaphore if this is the first user.
        ///
        /// This method uses an NSCondition to coordinate the "first user acquiring" state.
        /// Only one thread will wait on the semaphore; other concurrent threads wait on the
        /// condition and are woken when the first user successfully acquires access.
        /// This prevents multiple threads from serializing on the semaphore.
        ///
        /// - Parameter maxTimeout: Maximum time to wait for access.
        /// - Throws: `DispatchSemaphore.TimingError.timeout` if the wait times out.
        private func incrementUserCount(maxTimeout: DispatchTimeInterval = .seconds(2)) throws {
            // Compute deadline once at entry to avoid exceeding maxTimeout across retries
            let deadline = Self.timeoutDeadline(for: maxTimeout)

            while true {
                ndbUserStateCondition.lock()

                // If there are already users, just increment and return
                if ndbUserCount > 0 {
                    ndbUserCount += 1
                    ndbUserStateCondition.unlock()
                    return
                }

                // No users yet - check if someone is already acquiring
                if !ndbIsAcquiring {
                    // We are the first - mark as acquiring and go get the semaphore
                    ndbIsAcquiring = true
                    ndbUserStateCondition.unlock()

                    // Wait for semaphore WITHOUT holding the lock to prevent thread starvation
                    // Use do/catch to ensure ndbIsAcquiring is cleared even if wait throws
                    do {
                        let remaining = deadline.timeIntervalSinceNow
                        if remaining <= 0 {
                            throw DispatchSemaphore.TimingError.timeout
                        }
                        try ndbAccessSemaphore.waitOrThrow(timeout: .now() + .milliseconds(Int(remaining * 1_000)))
                    } catch {
                        // Clear acquiring flag and wake waiting threads before re-throwing
                        ndbUserStateCondition.lock()
                        ndbIsAcquiring = false
                        ndbUserStateCondition.broadcast()
                        ndbUserStateCondition.unlock()
                        throw error
                    }

                    // Successfully acquired - update state and wake waiting threads
                    ndbUserStateCondition.lock()
                    ndbIsAcquiring = false
                    ndbUserCount = 1
                    ndbUserStateCondition.broadcast()
                    ndbUserStateCondition.unlock()
                    return
                }

                // Someone else is acquiring - wait for them to finish
                let didSignal = ndbUserStateCondition.wait(until: deadline)
                ndbUserStateCondition.unlock()

                if !didSignal {
                    throw DispatchSemaphore.TimingError.timeout
                }
                // Loop back to check state again
            }
        }

        /// Decrements the active user count and signals when database can close.
        ///
        /// Acquires `ndbUserStateCondition` to safely decrement `ndbUserCount`.
        /// When count reaches zero, signals `ndbAccessSemaphore` to unblock
        /// any pending close operation. Thread-safe via internal locking.
        private func decrementUserCount() {
            ndbUserStateCondition.lock()
            defer { ndbUserStateCondition.unlock() }

            ndbUserCount -= 1
            // Signal that ndb can close if we have zero users using ndb
            if ndbUserCount == 0 {
                ndbAccessSemaphore.signal()
            }
        }

        /// Converts a DispatchTimeInterval into a Date deadline for NSCondition waits.
        private static func timeoutDeadline(for interval: DispatchTimeInterval) -> Date {
            switch interval {
            case .seconds(let seconds):
                return Date().addingTimeInterval(TimeInterval(seconds))
            case .milliseconds(let milliseconds):
                return Date().addingTimeInterval(TimeInterval(milliseconds) / 1_000.0)
            case .microseconds(let microseconds):
                return Date().addingTimeInterval(TimeInterval(microseconds) / 1_000_000.0)
            case .nanoseconds(let nanoseconds):
                return Date().addingTimeInterval(TimeInterval(nanoseconds) / 1_000_000_000.0)
            case .never:
                return .distantFuture
            @unknown default:
                return .distantFuture
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
