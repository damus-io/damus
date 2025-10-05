//
//  SubscriptionManager.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-03-25.
//
import Foundation
import os


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
        private let experimentalLocalRelayModelSupport: Bool
        
        private static let logger = Logger(
            subsystem: Constants.MAIN_APP_BUNDLE_IDENTIFIER,
            category: "subscription_manager"
        )
        
        let EXTRA_VERBOSE_LOGGING: Bool = false
        
        init(pool: RelayPool, ndb: Ndb, experimentalLocalRelayModelSupport: Bool) {
            self.pool = pool
            self.ndb = ndb
            self.taskManager = TaskManager()
            self.experimentalLocalRelayModelSupport = experimentalLocalRelayModelSupport
        }
        
        // MARK: - Subscribing and Streaming data from Nostr
        
        /// Streams notes until the EOSE signal
        func streamExistingEvents(filters: [NostrFilter], to desiredRelays: [RelayURL]? = nil, timeout: Duration? = nil, streamMode: StreamMode? = nil, id: UUID? = nil) -> AsyncStream<NdbNoteLender> {
            let timeout = timeout ?? .seconds(10)
            return AsyncStream<NdbNoteLender> { continuation in
                let streamingTask = Task {
                    outerLoop: for await item in self.advancedStream(filters: filters, to: desiredRelays, timeout: timeout, streamMode: streamMode, id: id) {
                        try Task.checkCancellation()
                        switch item {
                        case .event(let lender):
                            continuation.yield(lender)
                        case .eose:
                            break outerLoop
                        case .ndbEose:
                            continue
                        case .networkEose:
                            continue
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
        func timedStream(filters: [NostrFilter], to desiredRelays: [RelayURL]? = nil, timeout: Duration, streamMode: StreamMode? = nil, id: UUID? = nil) -> AsyncStream<NdbNoteLender> {
            return AsyncStream<NdbNoteLender> { continuation in
                let streamingTask = Task {
                    for await item in self.advancedStream(filters: filters, to: desiredRelays, timeout: timeout, streamMode: streamMode, id: id) {
                        try Task.checkCancellation()
                        switch item {
                        case .event(lender: let lender):
                            continuation.yield(lender)
                        case .eose: break
                        case .ndbEose: break
                        case .networkEose: break
                        }
                    }
                    continuation.finish()
                }
                continuation.onTermination = { @Sendable _ in
                    streamingTask.cancel()
                }
            }
        }
        
        /// Subscribes to notes indefinitely
        ///
        /// This is useful when simply streaming all events indefinitely
        func streamIndefinitely(filters: [NostrFilter], to desiredRelays: [RelayURL]? = nil, streamMode: StreamMode? = nil, id: UUID? = nil) -> AsyncStream<NdbNoteLender> {
            return AsyncStream<NdbNoteLender> { continuation in
                let streamingTask = Task {
                    for await item in self.advancedStream(filters: filters, to: desiredRelays, streamMode: streamMode, id: id) {
                        try Task.checkCancellation()
                        switch item {
                        case .event(lender: let lender):
                            continuation.yield(lender)
                        case .eose:
                            break
                        case .ndbEose:
                            break
                        case .networkEose:
                            break
                        }
                    }
                }
                continuation.onTermination = { @Sendable _ in
                    streamingTask.cancel()
                }
            }
        }
        
        /// Subscribes to data from the user's relays
        func advancedStream(filters: [NostrFilter], to desiredRelays: [RelayURL]? = nil, timeout: Duration? = nil, streamMode: StreamMode? = nil, id: UUID? = nil) -> AsyncStream<StreamItem> {
            return AsyncStream<StreamItem> { continuation in
                let subscriptionId = id ?? UUID()
                let startTime = CFAbsoluteTimeGetCurrent()
                Self.logger.info("Starting subscription \(subscriptionId.uuidString, privacy: .public): \(filters.debugDescription, privacy: .private)")
                let multiSessionStreamingTask = Task {
                    while !Task.isCancelled {
                        do {
                            guard !self.ndb.is_closed else {
                                Self.logger.info("\(subscriptionId.uuidString, privacy: .public): Ndb closed. Sleeping for 1 second before resuming.")
                                try await Task.sleep(nanoseconds: 1_000_000_000)
                                continue
                            }
                            guard self.pool.open else {
                                Self.logger.info("\(subscriptionId.uuidString, privacy: .public): RelayPool closed. Sleeping for 1 second before resuming.")
                                try await Task.sleep(nanoseconds: 1_000_000_000)
                                continue
                            }
                            Self.logger.info("\(subscriptionId.uuidString, privacy: .public): Streaming.")
                            for await item in self.sessionSubscribe(filters: filters, to: desiredRelays, streamMode: streamMode, id: id) {
                                try Task.checkCancellation()
                                continuation.yield(item)
                            }
                            Self.logger.info("\(subscriptionId.uuidString, privacy: .public): Session subscription ended. Sleeping for 1 second before resuming.")
                            try await Task.sleep(nanoseconds: 1_000_000_000)
                        }
                        catch {
                            Self.logger.error("Session subscription \(subscriptionId.uuidString, privacy: .public): Error: \(error.localizedDescription, privacy: .public)")
                        }
                    }
                    Self.logger.info("\(subscriptionId.uuidString, privacy: .public): Terminated.")
                }
                let timeoutTask = Task {
                    if let timeout {
                        try await Task.sleep(for: timeout)
                        continuation.finish()   // End the stream due to timeout.
                    }
                }
                continuation.onTermination = { @Sendable _ in
                    Self.logger.info("\(subscriptionId.uuidString, privacy: .public): Cancelled.")
                    multiSessionStreamingTask.cancel()
                    timeoutTask.cancel()
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
        private func sessionSubscribe(filters: [NostrFilter], to desiredRelays: [RelayURL]? = nil, streamMode: StreamMode? = nil, id: UUID? = nil) -> AsyncStream<StreamItem> {
            let id = id ?? UUID()
            let streamMode = streamMode ?? defaultStreamMode()
            return AsyncStream<StreamItem> { continuation in
                let startTime = CFAbsoluteTimeGetCurrent()
                Self.logger.debug("Session subscription \(id.uuidString, privacy: .public): Started")
                var ndbEOSEIssued = false
                var networkEOSEIssued = false
                
                // This closure function issues (yields) an EOSE signal to the stream if all relevant conditions are met
                let yieldEOSEIfReady = {
                    let connectedToNetwork = self.pool.network_monitor.currentPath.status == .satisfied
                    // In normal mode: Issuing EOSE requires EOSE from both NDB and the network, since they are all considered separate relays
                    // In experimental local relay model mode: Issuing EOSE requires only EOSE from NDB, since that is the only relay that "matters"
                    let canIssueEOSE = switch streamMode {
                    case .ndbFirst: (ndbEOSEIssued)
                    case .ndbAndNetworkParallel: (ndbEOSEIssued && (networkEOSEIssued || !connectedToNetwork))
                    }
                    
                    if canIssueEOSE {
                        Self.logger.debug("Session subscription \(id.uuidString, privacy: .public): Issued EOSE for session. Elapsed: \(CFAbsoluteTimeGetCurrent() - startTime, format: .fixed(precision: 2), privacy: .public) seconds")
                        continuation.yield(.eose)
                    }
                }
                
                let ndbStreamTask = Task {
                    do {
                        for await item in try self.ndb.subscribe(filters: try filters.map({ try NdbFilter(from: $0) })) {
                            try Task.checkCancellation()
                            switch item {
                            case .eose:
                                Self.logger.debug("Session subscription \(id.uuidString, privacy: .public): Received EOSE from nostrdb. Elapsed: \(CFAbsoluteTimeGetCurrent() - startTime, format: .fixed(precision: 2), privacy: .public) seconds")
                                continuation.yield(.ndbEose)
                                ndbEOSEIssued = true
                                yieldEOSEIfReady()
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
                        Self.logger.error("Session subscription \(id.uuidString, privacy: .public): NDB streaming error: \(error.localizedDescription, privacy: .public)")
                    }
                    Self.logger.debug("Session subscription \(id.uuidString, privacy: .public): NDB streaming ended")
                    continuation.finish()
                }
                let streamTask = Task {
                    do {
                        for await item in self.pool.subscribe(filters: filters, to: desiredRelays, id: id) {
                            // NO-OP. Notes will be automatically ingested by NostrDB
                            // TODO: Improve efficiency of subscriptions?
                            try Task.checkCancellation()
                            switch item {
                            case .event(let event):
                                if EXTRA_VERBOSE_LOGGING {
                                    Self.logger.debug("Session subscription \(id.uuidString, privacy: .public): Received kind \(event.kind, privacy: .public) event with id \(event.id.hex(), privacy: .private) from the network")
                                }
                                switch streamMode {
                                case .ndbFirst:
                                    break   // NO-OP
                                case .ndbAndNetworkParallel:
                                    continuation.yield(.event(lender: NdbNoteLender(ownedNdbNote: event)))
                                }
                            case .eose:
                                Self.logger.debug("Session subscription \(id.uuidString, privacy: .public): Received EOSE from the network. Elapsed: \(CFAbsoluteTimeGetCurrent() - startTime, format: .fixed(precision: 2), privacy: .public) seconds")
                                continuation.yield(.networkEose)
                                networkEOSEIssued = true
                                yieldEOSEIfReady()
                            }
                        }
                    }
                    catch {
                        Self.logger.error("Session subscription \(id.uuidString, privacy: .public): Network streaming error: \(error.localizedDescription, privacy: .public)")
                    }
                    Self.logger.debug("Session subscription \(id.uuidString, privacy: .public): Network streaming ended")
                    continuation.finish()
                }
                
                Task {
                    // Add the ndb streaming task to the task manager so that it can be cancelled when the app is backgrounded
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
        
        // MARK: - Utility functions
        
        private func defaultStreamMode() -> StreamMode {
            self.experimentalLocalRelayModelSupport ? .ndbFirst : .ndbAndNetworkParallel
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
            for await noteLender in self.streamExistingEvents(filters: filters, to: to, timeout: timeout) {
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
            
            for await noteLender in self.streamExistingEvents(filters: [filter], to: targetRelays, timeout: timeout) {
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
            
            for await noteLender in self.streamExistingEvents(filters: [filter], to: find_from) {
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
            
            private static let logger = Logger(
                subsystem: "com.jb55.damus",
                category: "subscription_manager.task_manager"
            )
            
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
                    await withTaskGroup { group in
                        Self.logger.info("Cancelling all SubscriptionManager tasks")
                    // Start each task cancellation in parallel for faster execution
                    for (taskId, _) in self.tasks {
                        Self.logger.info("Cancelling SubscriptionManager task \(taskId.uuidString, privacy: .public)")
                        group.addTask {
                            await self.cancelAndCleanUp(taskId: taskId)
                        }
                    }
                    // However, wait until all cancellations are complete to avoid race conditions.
                    for await value in group {
                        continue
                    }
                    Self.logger.info("Cancelled all SubscriptionManager tasks")
                }
            }
        }
    }
    
    enum StreamItem {
        /// An event which can be borrowed from NostrDB
        case event(lender: NdbNoteLender)
        /// The canonical generic "end of stored events", which depends on the stream mode. See `StreamMode` to see when this event is fired in relation to other EOSEs
        case eose
        /// "End of stored events" from NostrDB.
        case ndbEose
        /// "End of stored events" from all relays in `RelayPool`.
        case networkEose
        
        var debugDescription: String {
            switch self {
            case .event(lender: let lender):
                let detailedDescription = try? lender.borrow({ event in
                    "Note with ID: \(event.id.hex())"
                })
                return detailedDescription ?? "Some note"
            case .eose:
                return "EOSE"
            case .ndbEose:
                return "NDB EOSE"
            case .networkEose:
                return "NETWORK EOSE"
            }
        }
    }
    
    /// The mode of streaming
    enum StreamMode {
        /// Returns notes exclusively through NostrDB, treating it as the only channel for information in the pipeline. Generic EOSE is fired when EOSE is received from NostrDB
        case ndbFirst
        /// Returns notes from both NostrDB and the network, in parallel, treating it with similar importance against the network relays. Generic EOSE is fired when EOSE is received from both the network and NostrDB
        case ndbAndNetworkParallel
    }
}
