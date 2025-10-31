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
        
        func advancedStream(filters: [NostrFilter], to desiredRelays: [RelayURL]? = nil, timeout: Duration? = nil, streamMode: StreamMode? = nil, id: UUID? = nil) -> AsyncStream<StreamItem> {
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
                    case .ndbFirst, .ndbOnly: (ndbEOSEIssued)
                    case .ndbAndNetworkParallel: (ndbEOSEIssued && (networkEOSEIssued || !connectedToNetwork))
                    }
                    
                    if canIssueEOSE {
                        Self.logger.debug("Session subscription \(id.uuidString, privacy: .public): Issued EOSE for session. Elapsed: \(CFAbsoluteTimeGetCurrent() - startTime, format: .fixed(precision: 2), privacy: .public) seconds")
                        logStreamPipelineStats("SubscriptionManager_Advanced_Stream_\(id)", "Consumer_\(id)")
                        continuation.yield(.eose)
                    }
                }
                
                var networkStreamTask: Task<Void, any Error>? = nil
                var latestNoteTimestampSeen: UInt32? = nil
                
                let startNetworkStreamTask = {
                    guard streamMode.shouldStreamFromNetwork else { return }
                    networkStreamTask = Task {
                        while !Task.isCancelled {
                            let optimizedFilters = filters.map {
                                var optimizedFilter = $0
                                // Shift the since filter 2 minutes (120 seconds) before the last note timestamp
                                if let latestTimestamp = latestNoteTimestampSeen {
                                    optimizedFilter.since = latestTimestamp > 120 ? latestTimestamp - 120 : 0
                                }
                                return optimizedFilter
                            }
                            for await item in self.multiSessionNetworkStream(filters: optimizedFilters, to: desiredRelays, streamMode: streamMode, id: id) {
                                try Task.checkCancellation()
                                logStreamPipelineStats("SubscriptionManager_Network_Stream_\(id)", "SubscriptionManager_Advanced_Stream_\(id)")
                                switch item {
                                case .event(let lender):
                                    logStreamPipelineStats("SubscriptionManager_Advanced_Stream_\(id)", "Consumer_\(id)")
                                    continuation.yield(item)
                                case .eose:
                                    break   // Should not happen
                                case .ndbEose:
                                    break   // Should not happen
                                case .networkEose:
                                    logStreamPipelineStats("SubscriptionManager_Advanced_Stream_\(id)", "Consumer_\(id)")
                                    continuation.yield(item)
                                    networkEOSEIssued = true
                                    yieldEOSEIfReady()
                                }
                            }
                        }
                    }
                }
                
                if streamMode.optimizeNetworkFilter == false && streamMode.shouldStreamFromNetwork {
                    // Start streaming from the network straight away
                    startNetworkStreamTask()
                }
                
                let ndbStreamTask = Task {
                    while !Task.isCancelled {
                        for await item in self.multiSessionNdbStream(filters: filters, to: desiredRelays, streamMode: streamMode, id: id) {
                            try Task.checkCancellation()
                            logStreamPipelineStats("SubscriptionManager_Ndb_MultiSession_Stream_\(id)", "SubscriptionManager_Advanced_Stream_\(id)")
                            switch item {
                            case .event(let lender):
                                logStreamPipelineStats("SubscriptionManager_Advanced_Stream_\(id)", "Consumer_\(id)")
                                try? lender.borrow({ event in
                                    if let latestTimestamp = latestNoteTimestampSeen {
                                        latestNoteTimestampSeen = max(latestTimestamp, event.createdAt)
                                    }
                                    else {
                                        latestNoteTimestampSeen = event.createdAt
                                    }
                                })
                                continuation.yield(item)
                            case .eose:
                                break   // Should not happen
                            case .ndbEose:
                                logStreamPipelineStats("SubscriptionManager_Advanced_Stream_\(id)", "Consumer_\(id)")
                                continuation.yield(item)
                                ndbEOSEIssued = true
                                if streamMode.optimizeNetworkFilter && streamMode.shouldStreamFromNetwork {
                                    startNetworkStreamTask()
                                }
                                yieldEOSEIfReady()
                            case .networkEose:
                                break   // Should not happen
                            }
                        }
                    }
                }
                
                continuation.onTermination = { @Sendable _ in
                    networkStreamTask?.cancel()
                    ndbStreamTask.cancel()
                }
            }
        }
        
        private func multiSessionNetworkStream(filters: [NostrFilter], to desiredRelays: [RelayURL]? = nil, streamMode: StreamMode? = nil, id: UUID? = nil) -> AsyncStream<StreamItem> {
            let id = id ?? UUID()
            let streamMode = streamMode ?? defaultStreamMode()
            return AsyncStream<StreamItem> { continuation in
                let startTime = CFAbsoluteTimeGetCurrent()
                Self.logger.debug("Network subscription \(id.uuidString, privacy: .public): Started")
                
                let streamTask = Task {
                    while await !self.pool.open {
                        Self.logger.info("\(id.uuidString, privacy: .public): RelayPool closed. Sleeping for 1 second before resuming.")
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                        continue
                    }
                    
                    do {
                        for await item in await self.pool.subscribe(filters: filters, to: desiredRelays, id: id) {
                            try Task.checkCancellation()
                            logStreamPipelineStats("RelayPool_Handler_\(id)", "SubscriptionManager_Network_Stream_\(id)")
                            switch item {
                            case .event(let event):
                                switch streamMode {
                                case .ndbFirst, .ndbOnly:
                                    break   // NO-OP
                                case .ndbAndNetworkParallel:
                                    continuation.yield(.event(lender: NdbNoteLender(ownedNdbNote: event)))
                                }
                            case .eose:
                                Self.logger.debug("Session subscription \(id.uuidString, privacy: .public): Received EOSE from the network. Elapsed: \(CFAbsoluteTimeGetCurrent() - startTime, format: .fixed(precision: 2), privacy: .public) seconds")
                                continuation.yield(.networkEose)
                            }
                        }
                    }
                    catch {
                        Self.logger.error("Network subscription \(id.uuidString, privacy: .public): Streaming error: \(error.localizedDescription, privacy: .public)")
                    }
                    Self.logger.debug("Network subscription \(id.uuidString, privacy: .public): Network streaming ended")
                    continuation.finish()
                }
                
                continuation.onTermination = { @Sendable _ in
                    streamTask.cancel()
                }
            }
        }
        
        private func multiSessionNdbStream(filters: [NostrFilter], to desiredRelays: [RelayURL]? = nil, streamMode: StreamMode? = nil, id: UUID? = nil) -> AsyncStream<StreamItem> {
            return AsyncStream<StreamItem> { continuation in
                let subscriptionId = id ?? UUID()
                let startTime = CFAbsoluteTimeGetCurrent()
                Self.logger.info("Starting multi-session NDB subscription \(subscriptionId.uuidString, privacy: .public): \(filters.debugDescription, privacy: .private)")
                let multiSessionStreamingTask = Task {
                    while !Task.isCancelled {
                        do {
                            guard !self.ndb.is_closed else {
                                Self.logger.info("\(subscriptionId.uuidString, privacy: .public): Ndb closed. Sleeping for 1 second before resuming.")
                                try await Task.sleep(nanoseconds: 1_000_000_000)
                                continue
                            }
                            Self.logger.info("\(subscriptionId.uuidString, privacy: .public): Streaming from NDB.")
                            for await item in self.sessionNdbStream(filters: filters, to: desiredRelays, streamMode: streamMode, id: id) {
                                try Task.checkCancellation()
                                logStreamPipelineStats("SubscriptionManager_Ndb_Session_Stream_\(id?.uuidString ?? "NoID")", "SubscriptionManager_Ndb_MultiSession_Stream_\(id?.uuidString ?? "NoID")")
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
                continuation.onTermination = { @Sendable _ in
                    Self.logger.info("\(subscriptionId.uuidString, privacy: .public): Cancelled multi-session NDB stream.")
                    multiSessionStreamingTask.cancel()
                }
            }
        }
        
        private func sessionNdbStream(filters: [NostrFilter], to desiredRelays: [RelayURL]? = nil, streamMode: StreamMode? = nil, id: UUID? = nil) -> AsyncStream<StreamItem> {
            let id = id ?? UUID()
            //let streamMode = streamMode ?? defaultStreamMode()
            return AsyncStream<StreamItem> { continuation in
                let startTime = CFAbsoluteTimeGetCurrent()
                Self.logger.debug("Session subscription \(id.uuidString, privacy: .public): Started")
                
                let ndbStreamTask = Task {
                    do {
                        for await item in try self.ndb.subscribe(filters: try filters.map({ try NdbFilter(from: $0) })) {
                            try Task.checkCancellation()
                            switch item {
                            case .eose:
                                Self.logger.debug("Session subscription \(id.uuidString, privacy: .public): Received EOSE from nostrdb. Elapsed: \(CFAbsoluteTimeGetCurrent() - startTime, format: .fixed(precision: 2), privacy: .public) seconds")
                                continuation.yield(.ndbEose)
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
                
                Task {
                    // Add the ndb streaming task to the task manager so that it can be cancelled when the app is backgrounded
                    let ndbStreamTaskId = await self.taskManager.add(task: ndbStreamTask)
                    
                    continuation.onTermination = { @Sendable _ in
                        Task {
                            await self.taskManager.cancelAndCleanUp(taskId: ndbStreamTaskId)
                        }
                    }
                }
            }
        }
        
        // MARK: - Utility functions
        
        private func defaultStreamMode() -> StreamMode {
            self.experimentalLocalRelayModelSupport ? .ndbFirst(optimizeNetworkFilter: false) : .ndbAndNetworkParallel(optimizeNetworkFilter: false)
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
            outerLoop: for await item in await self.pool.subscribe(filters: [NostrFilter(ids: [noteId], limit: 1)], to: targetRelays, eoseTimeout: timeout) {
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
        /// `optimizeNetworkFilter`: Returns notes from ndb, then streams from the network with an added "since" filter set to the latest note stored on ndb.
        case ndbFirst(optimizeNetworkFilter: Bool)
        /// Returns notes from both NostrDB and the network, in parallel, treating it with similar importance against the network relays. Generic EOSE is fired when EOSE is received from both the network and NostrDB
        /// `optimizeNetworkFilter`: Returns notes from ndb, then streams from the network with an added "since" filter set to the latest note stored on ndb.
        case ndbAndNetworkParallel(optimizeNetworkFilter: Bool)
        /// Ignores the network. Used for testing purposes
        case ndbOnly
        
        var optimizeNetworkFilter: Bool {
            switch self {
            case .ndbFirst(optimizeNetworkFilter: let optimizeNetworkFilter):
                return optimizeNetworkFilter
            case .ndbAndNetworkParallel(optimizeNetworkFilter: let optimizeNetworkFilter):
                return optimizeNetworkFilter
            case .ndbOnly:
                return false
            }
        }
        
        var shouldStreamFromNetwork: Bool {
            switch self {
            case .ndbFirst:
                return true
            case .ndbAndNetworkParallel:
                return true
            case .ndbOnly:
                return false
            }
        }
    }
}
