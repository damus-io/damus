//
//  AsyncStreamUtilities.swift
//  damus
//
//  Created by Daniel D'Aquino on 2026-01-15.
//


extension AsyncThrowingStream where Failure == any Error {
    /// Convenience initializer for an async throwing stream that uses an async task to stream items
    static func with(task: @escaping (_ continuation: AsyncThrowingStream<Element, Failure>.Continuation) async throws -> Void) -> AsyncThrowingStream<Element, Failure> {
        return AsyncThrowingStream<Element, Failure> { continuation in
            let streamTask = Task {
                do {
                    try await task(continuation)
                }
                catch {
                    continuation.finish(throwing: error)
                }
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                streamTask.cancel()
            }
        }
    }
}

extension AsyncStream {
    /// Convenience initializer for an async stream that uses an async task to stream items
    static func with(task: @escaping (_ continuation: AsyncStream<Element>.Continuation) async -> Void) -> AsyncStream<Element> {
        return AsyncStream<Element> { continuation in
            let streamTask = Task {
                await task(continuation)
                continuation.finish()
            }
            continuation.onTermination = { @Sendable _ in
                streamTask.cancel()
            }
        }
    }
}
