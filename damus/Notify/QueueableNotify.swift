//
//  QueueableNotify.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-02-14.
//

/// This notifies another object about some payload,
/// with automatic "queueing" of messages if there are no listeners.
///
/// When used as a singleton, this can be used to easily send notifications to be handled at the app-level.
///
/// This serves the same purpose as `Notify`, except this implements the queueing of messages,
/// which means that messages can be handled even if the listener is not instantiated yet.
///
/// **Example:** The app delegate can send some events that need handling from `ContentView` — but some can occur before `ContentView` is even instantiated.
///
///
///  ## Usage notes
///
///  - This code was mainly written to have one listener at a time. Have more than one listener may be possible, but this class has not been tested/optimized for that purpose.
///
///
///  ## Implementation notes
///
///  - This makes heavy use of `AsyncStream` and continuations, because that allows complexities here to be handled elegantly with a simple "for-in" loop
///         - Without this, it would take a couple of callbacks and manual handling of queued items to achieve the same effect
///  - Modeled as an `actor` for extra thread-safety
actor QueueableNotify<T: Sendable> {
    /// The continuation, which allows us to publish new items to the listener
    /// If `nil`, that means there is no listeners to the stream, which is used for determining whether to queue new incoming items.
    private var continuation: AsyncStream<T>.Continuation?
    /// Holds queue items
    private var queue: [T] = []
    /// The maximum amount of items allowed in the queue. Older items will be discarded from the queue after it is full
    var maxQueueItems: Int

    /// Initializes the object
    /// - Parameter maxQueueItems: The maximum amount of items allowed in the queue. Older items will be discarded from the queue after it is full
    init(maxQueueItems: Int) {
        self.maxQueueItems = maxQueueItems
    }

    /// The async stream, used for listening for notifications
    ///
    /// This will first stream the queued "inbox" items that the listener may have missed, and then it will do a real-time stream of new items as they come in.
    ///
    /// Example:
    ///
    /// ```swift
    /// for await notification in queueableNotify.stream {
    ///         // Do something with the notification
    /// }
    /// ```
    var stream: AsyncStream<T> {
        return AsyncStream { continuation in
            // Stream queued "inbox" items that the listener may have missed
            for item in queue {
                continuation.yield(item)
            }

            // Clean up if the stream closes
            continuation.onTermination = { continuation in
                Task { await self.cleanup() }
            }

            // Point to this stream, so that it can receive new updates
            self.continuation = continuation
        }
    }

    /// Cleans up after a stream is closed by the listener
    private func cleanup() {
        self.continuation = nil   // This will cause new items to be queued for when another listener is attached
    }

    /// Adds a new notification item to be handled by a listener.
    ///
    /// This will automatically stream the new item to the listener, or queue the item if no one is listening
    func add(item: T) {
        while queue.count >= maxQueueItems { queue.removeFirst() }  // Ensures queue stays within the desired size
        guard let continuation else {
            // No one is listening, queue it (send it to an inbox for later handling)
            queue.append(item)
            return
        }
        // Send directly to the active listener stream
        continuation.yield(item)
    }
}
