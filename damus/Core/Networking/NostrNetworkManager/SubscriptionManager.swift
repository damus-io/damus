//
//  SubscriptionManager.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-03-25.
//
import Foundation

extension NostrNetworkManager {
    /// Reads or fetches information from RelayPool and NostrDB, and provides an easier and unified higher-level interface.
    ///
    /// ## Implementation notes
    ///
    /// - This class will be a key part of the local relay model migration. Most higher-level code should fetch content from this class, which will properly setup the correct relay pool subscriptions, and provide a stream from NostrDB for higher performance and reliability.
    class SubscriptionManager {
        private let pool: RelayPool
        private var ndb: Ndb
        private var taskManager: TaskManager
        
        init(pool: RelayPool, ndb: Ndb) {
            self.pool = pool
            self.ndb = ndb
            self.taskManager = TaskManager()
        }
        
        // MARK: - Reading data from Nostr
        
        /// Subscribes to data from user's relays, for a maximum period of time — after which the stream will end.
        ///
        /// This is useful when waiting for some specific data from Nostr, but not indefinitely.
        func subscribe(filters: [NostrFilter], to desiredRelays: [RelayURL]? = nil, timeout: Duration) -> AsyncStream<StreamItem> {
            return AsyncStream<StreamItem> { continuation in
                let streamingTask = Task {
                    for await item in self.subscribe(filters: filters, to: desiredRelays) {
                        try Task.checkCancellation()
                        continuation.yield(item)
                    }
                }
                let timeoutTask = Task {
                    try await Task.sleep(for: timeout)
                    continuation.finish()   // End the stream due to timeout.
                }
                continuation.onTermination = { @Sendable _ in
                    timeoutTask.cancel()
                    streamingTask.cancel()
                }
            }
        }
        
        /// Subscribes to data from the user's relays
        ///
        /// ## Implementation notes
        ///
        /// - When we migrate to the local relay model, we should modify this function to stream directly from NostrDB
        ///
        /// - Parameter filters: The nostr filters to specify what kind of data to subscribe to
        /// - Returns: An async stream of nostr data
        func subscribe(filters: [NostrFilter], to desiredRelays: [RelayURL]? = nil) -> AsyncStream<StreamItem> {
            return AsyncStream<StreamItem> { continuation in
                let subscriptionId = UUID()
                Log.info("Starting subscription %s: %s", for: .subscription_manager, subscriptionId.uuidString, filters.debugDescription)
                let multiSessionStreamingTask = Task {
                    while !Task.isCancelled {
                        do {
                            guard !self.ndb.is_closed else {
                                Log.info("%s: Ndb closed. Sleeping for 1 second before resuming.", for: .subscription_manager, subscriptionId.uuidString)
                                try await Task.sleep(nanoseconds: 1_000_000_000)
                                continue
                            }
                            guard self.pool.open else {
                                Log.info("%s: RelayPool closed. Sleeping for 1 second before resuming.", for: .subscription_manager, subscriptionId.uuidString)
                                try await Task.sleep(nanoseconds: 1_000_000_000)
                                continue
                            }
                            Log.info("%s: Streaming.", for: .subscription_manager, subscriptionId.uuidString)
                            for await item in self.sessionSubscribe(filters: filters, to: desiredRelays) {
                                try Task.checkCancellation()
                                continuation.yield(item)
                            }
                            Log.info("%s: Session subscription ended. Sleeping for 1 second before resuming.", for: .subscription_manager, subscriptionId.uuidString)
                            try await Task.sleep(nanoseconds: 1_000_000_000)
                        }
                        catch {
                            Log.error("%s: Error: %s", for: .subscription_manager, subscriptionId.uuidString, error.localizedDescription)
                        }
                    }
                    Log.info("%s: Terminated.", for: .subscription_manager, subscriptionId.uuidString)
                }
                continuation.onTermination = { @Sendable _ in
                    Log.info("%s: Cancelled.", for: .subscription_manager, subscriptionId.uuidString)
                    multiSessionStreamingTask.cancel()
                }
            }
        }
        
        /// Subscribes to data from the user's relays
        ///
        /// Only survives for a single session. This exits after the app is backgrounded
        ///
        /// ## Implementation notes
        ///
        /// - When we migrate to the local relay model, we should modify this function to stream directly from NostrDB
        ///
        /// - Parameter filters: The nostr filters to specify what kind of data to subscribe to
        /// - Returns: An async stream of nostr data
        private func sessionSubscribe(filters: [NostrFilter], to desiredRelays: [RelayURL]? = nil) -> AsyncStream<StreamItem> {
            return AsyncStream<StreamItem> { continuation in
                let ndbStreamTask = Task {
                    do {
                        for await item in try self.ndb.subscribe(filters: try filters.map({ try NdbFilter(from: $0) })) {
                            try Task.checkCancellation()
                            switch item {
                            case .eose:
                                continuation.yield(.eose)
                            case .event(let noteKey):
                                let lender: NdbNoteLender = { lend in
                                    guard let ndbNoteTxn = self.ndb.lookup_note_by_key(noteKey) else {
                                        throw NdbNoteLenderError.errorLoadingNote
                                    }
                                    guard let unownedNote = UnownedNdbNote(ndbNoteTxn) else {
                                        throw NdbNoteLenderError.errorLoadingNote
                                    }
                                    lend(unownedNote)
                                }
                                try Task.checkCancellation()
                                continuation.yield(.event(borrow: lender))
                            }
                        }
                    }
                    catch {
                        Log.error("NDB streaming error: %s", for: .subscription_manager, error.localizedDescription)
                    }
                    continuation.finish()
                }
                let streamTask = Task {
                    do {
                        for await item in self.pool.subscribe(filters: filters, to: desiredRelays) {
                            // NO-OP. Notes will be automatically ingested by NostrDB
                            // TODO: Improve efficiency of subscriptions?
                            try Task.checkCancellation()
                            switch item {
                            case .event(let event):
                                Log.debug("Session subscribe: Received kind %d event with id %s from the network", for: .subscription_manager, event.kind, event.id.hex())
                            case .eose:
                                Log.debug("Session subscribe: Received EOSE from the network", for: .subscription_manager)
                            }
                        }
                    }
                    catch {
                        Log.error("Network streaming error: %s", for: .subscription_manager, error.localizedDescription)
                    }
                    continuation.finish()
                }
                
                Task {
                    let ndbStreamTaskId = await self.taskManager.add(task: ndbStreamTask)
                    let streamTaskId = await self.taskManager.add(task: streamTask)
                    
                    continuation.onTermination = { @Sendable _ in
                        Task {
                            await self.taskManager.cancelAndCleanUp(taskId: ndbStreamTaskId)
                            await self.taskManager.cancelAndCleanUp(taskId: streamTaskId)
                        }
                    }
                }
            }
        }
        
        func cancelAllTasks() async {
            await self.taskManager.cancelAllTasks()
        }
        
        actor TaskManager {
            private var tasks: [UUID: Task<Void, Never>] = [:]
            
            func add(task: Task<Void, Never>) -> UUID {
                let taskId = UUID()
                self.tasks[taskId] = task
                return taskId
            }
            
            func cancelAndCleanUp(taskId: UUID) async {
                self.tasks[taskId]?.cancel()
                await self.tasks[taskId]?.value
                self.tasks[taskId] = nil
                return
            }
            
            func cancelAllTasks() async {
                Log.info("Cancelling all SubscriptionManager tasks", for: .subscription_manager)
                for (taskId, _) in self.tasks {
                    Log.info("Cancelling SubscriptionManager task %s", for: .subscription_manager, taskId.uuidString)
                    await cancelAndCleanUp(taskId: taskId)
                }
                Log.info("Cancelled all SubscriptionManager tasks", for: .subscription_manager)
            }
        }
    }
    
    enum StreamItem {
        /// An event which can be borrowed from NostrDB
        case event(borrow: NdbNoteLender)
        /// The end of stored events
        case eose
    }
}
