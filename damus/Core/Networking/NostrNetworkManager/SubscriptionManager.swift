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
        
        // MARK: - Subscribing and Streaming data from Nostr
        
        /// Streams notes until the EOSE signal
        func streamNotesUntilEndOfStoredEvents(filters: [NostrFilter], to desiredRelays: [RelayURL]? = nil, timeout: Duration? = nil) -> AsyncStream<NdbNoteLender> {
            let timeout = timeout ?? .seconds(10)
            return AsyncStream<NdbNoteLender> { continuation in
                let streamingTask = Task {
                    outerLoop: for await item in self.subscribe(filters: filters, to: desiredRelays, timeout: timeout) {
                        try Task.checkCancellation()
                        switch item {
                        case .event(let lender):
                            continuation.yield(lender)
                        case .eose:
                            break outerLoop
                        }
                    }
                    continuation.finish()
                }
                continuation.onTermination = { @Sendable _ in
                    streamingTask.cancel()
                }
            }
        }
        
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
                                let lender = NdbNoteLender(ndb: self.ndb, noteKey: noteKey)
                                try Task.checkCancellation()
                                guard let desiredRelays else {
                                    continuation.yield(.event(lender: lender))  // If no desired relays are specified, return all notes we see.
                                    break
                                }
                                if try ndb.was(noteKey: noteKey, seenOnAnyOf: desiredRelays) {
                                    continuation.yield(.event(lender: lender))  // If desired relays were specified and this note was seen there, return it.
                                }
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
        
        // MARK: - Finding specific data from Nostr
        
        /// Finds a non-replaceable event based on a note ID
        func lookup(noteId: NoteId, to targetRelays: [RelayURL]? = nil, timeout: Duration? = nil) async throws -> NdbNoteLender? {
            let filter = NostrFilter(ids: [noteId], limit: 1)
            
            // Since note ids point to immutable objects, we can do a simple ndb lookup first
            if let noteKey = self.ndb.lookup_note_key(noteId) {
                return NdbNoteLender(ndb: self.ndb, noteKey: noteKey)
            }
            
            // Not available in local ndb, stream from network
            outerLoop: for await item in self.pool.subscribe(filters: [NostrFilter(ids: [noteId], limit: 1)], to: targetRelays, eoseTimeout: timeout) {
                switch item {
                case .event(let event):
                    return NdbNoteLender(ownedNdbNote: event)
                case .eose:
                    break outerLoop
                }
            }
            
            return nil
        }
        
        func query(filters: [NostrFilter], to: [RelayURL]? = nil, timeout: Duration? = nil) async -> [NostrEvent] {
            var events: [NostrEvent] = []
            for await noteLender in self.streamNotesUntilEndOfStoredEvents(filters: filters, to: to, timeout: timeout) {
                noteLender.justUseACopy({ events.append($0) })
            }
            return events
        }
        
        /// Finds a replaceable event based on an `naddr` address.
        ///
        /// - Parameters:
        ///   - naddr: the `naddr` address
        func lookup(naddr: NAddr, to targetRelays: [RelayURL]? = nil, timeout: Duration? = nil) async -> NostrEvent? {
            var nostrKinds: [NostrKind]? = NostrKind(rawValue: naddr.kind).map { [$0] }

            let filter = NostrFilter(kinds: nostrKinds, authors: [naddr.author])
            
            for await noteLender in self.streamNotesUntilEndOfStoredEvents(filters: [filter], to: targetRelays, timeout: timeout) {
                // TODO: This can be refactored to borrow the note instead of copying it. But we need to implement `referenced_params` on `UnownedNdbNote` to do so
                guard let event = noteLender.justGetACopy() else { continue }
                if event.referenced_params.first?.param.string() == naddr.identifier {
                    return event
                }
            }
            
            return nil
        }
        
        // TODO: Improve this. This is mostly intact to keep compatibility with its predecessor, but we can do better
        func findEvent(query: FindEvent) async -> FoundEvent? {
            var filter: NostrFilter? = nil
            let find_from = query.find_from
            let query = query.type
            
            switch query {
            case .profile(let pubkey):
                if let profile_txn = self.ndb.lookup_profile(pubkey),
                   let record = profile_txn.unsafeUnownedValue,
                   record.profile != nil
                {
                    return .profile(pubkey)
                }
                filter = NostrFilter(kinds: [.metadata], limit: 1, authors: [pubkey])
            case .event(let evid):
                if let event = self.ndb.lookup_note(evid)?.unsafeUnownedValue?.to_owned() {
                    return .event(event)
                }
                filter = NostrFilter(ids: [evid], limit: 1)
            }
            
            var attempts: Int = 0
            var has_event = false
            guard let filter else { return nil }
            
            for await noteLender in self.streamNotesUntilEndOfStoredEvents(filters: [filter], to: find_from) {
                let foundEvent: FoundEvent? = try? noteLender.borrow({ event in
                    switch query {
                    case .profile:
                        if event.known_kind == .metadata {
                            return .profile(event.pubkey)
                        }
                    case .event:
                        return .event(event.toOwned())
                    }
                    return nil
                })
                if let foundEvent {
                    return foundEvent
                }
            }

            return nil
        }
        
        // MARK: - Task management
        
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
        case event(lender: NdbNoteLender)
        /// The end of stored events
        case eose
    }
}
