//
//  NdbUseLock.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-11-12.
//

import Dispatch
import Synchronization

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
        /// Number of functions using the `ndb` object (for reading or writing data)
        private let ndbUserCount = Mutex<UInt>(0)
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
        
        private func incrementUserCount(maxTimeout: DispatchTimeInterval = .seconds(2)) throws {
            try ndbUserCount.withLock { currentCount in
                // Signal that ndb cannot close while we have at least one user using ndb
                if currentCount == 0 {
                    try ndbAccessSemaphore.waitOrThrow(timeout: .now() + maxTimeout)
                }
                currentCount += 1
            }
        }
        
        private func decrementUserCount() {
            ndbUserCount.withLock { currentCount in
                currentCount -= 1
                // Signal that ndb can close if we have zero users using ndb
                if currentCount == 0 {
                    ndbAccessSemaphore.signal()
                }
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
            let ndbIsOpen = operation()
            if ndbIsOpen {
                ndbAccessSemaphore.signal()
            }
        }
        
        /// Marks `ndb` as open to allow other users to use it. Do not call this more than once
        func markNdbOpen() {
            ndbAccessSemaphore.signal()
        }
        
        private func incrementUserCount(maxTimeout: DispatchTimeInterval = .seconds(2)) throws {
            if ndbUserCount == 0 {
                try ndbAccessSemaphore.waitOrThrow(timeout: .now() + maxTimeout)
            }
            ndbUserCount += 1
        }
        
        private func decrementUserCount() {
            ndbUserCount -= 1
            // Signal that ndb can close if we have zero users using ndb
            if ndbUserCount == 0 {
                ndbAccessSemaphore.signal()
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
