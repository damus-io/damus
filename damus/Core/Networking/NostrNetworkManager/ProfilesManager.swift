//
//  ProfilesManager.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-09-19.
//
import Foundation

extension NostrNetworkManager {
    /// Efficiently manages getting profile metadata from the network and NostrDB without too many relay subscriptions
    ///
    /// This is necessary because relays have a limit on how many subscriptions can be sent to relays at one given time.
    actor ProfilesManager {
        private var profileListenerTask: Task<Void, any Error>? = nil
        private var subscriptionSwitcherTask: Task<Void, any Error>? = nil
        private var subscriptionNeedsUpdate: Bool = false
        private let subscriptionManager: SubscriptionManager
        private let ndb: Ndb
        private var streams: [Pubkey: [UUID: ProfileStreamInfo]]
        
        
        // MARK: - Initialization and deinitialization
        
        init(subscriptionManager: SubscriptionManager, ndb: Ndb) {
            self.subscriptionManager = subscriptionManager
            self.ndb = ndb
            self.streams = [:]
        }
        
        deinit {
            self.subscriptionSwitcherTask?.cancel()
            self.profileListenerTask?.cancel()
        }
        
        // MARK: - Task management
        
        func load() {
            self.restartProfileListenerTask()
            self.subscriptionSwitcherTask?.cancel()
            self.subscriptionSwitcherTask = Task {
                while true {
                    try await Task.sleep(for: .seconds(1))
                    try Task.checkCancellation()
                    if subscriptionNeedsUpdate {
                        try Task.checkCancellation()
                        self.restartProfileListenerTask()
                        subscriptionNeedsUpdate = false
                    }
                }
            }
        }
        
        func stop() async {
            await withTaskGroup { group in
                // Spawn each cancellation in parallel for better execution speed
                group.addTask {
                    await self.subscriptionSwitcherTask?.cancel()
                    try? await self.subscriptionSwitcherTask?.value
                }
                group.addTask {
                    await self.profileListenerTask?.cancel()
                    try? await self.profileListenerTask?.value
                }
                // But await for all of them to be done before returning to avoid race conditions
                for await value in group { continue }
            }
        }
        
        private func restartProfileListenerTask() {
            self.profileListenerTask?.cancel()
            self.profileListenerTask = Task {
                try await self.listenToProfileChanges()
            }
        }
        
        
        // MARK: - Listening and publishing of profile changes
        
        private func listenToProfileChanges() async throws {
            let pubkeys = Array(streams.keys)
            guard pubkeys.count > 0 else { return }
            let profileFilter = NostrFilter(kinds: [.metadata], authors: pubkeys)
            try Task.checkCancellation()
            for await ndbLender in self.subscriptionManager.streamIndefinitely(filters: [profileFilter], streamMode: .ndbFirst(optimizeNetworkFilter: false)) {
                try Task.checkCancellation()
                try? ndbLender.borrow { ev in
                    publishProfileUpdates(metadataEvent: ev)
                }
                try Task.checkCancellation()
            }
        }
        
        private func publishProfileUpdates(metadataEvent: borrowing UnownedNdbNote) {
            let now = UInt64(Date.now.timeIntervalSince1970)
            ndb.write_profile_last_fetched(pubkey: metadataEvent.pubkey, fetched_at: now)
            
            if let relevantStreams = streams[metadataEvent.pubkey] {
                // If we have the user metadata event in ndb, then we should have the profile record as well.
                guard let profile = ndb.lookup_profile(metadataEvent.pubkey) else { return }
                for relevantStream in relevantStreams.values {
                    relevantStream.continuation.yield(profile)
                }
            }
        }
        
        
        // MARK: - Streaming interface
        
        func streamProfile(pubkey: Pubkey) -> AsyncStream<ProfileStreamItem> {
            return AsyncStream<ProfileStreamItem> { continuation in
                let stream = ProfileStreamInfo(continuation: continuation)
                self.add(pubkey: pubkey, stream: stream)
                
                continuation.onTermination = { @Sendable _ in
                    Task { await self.removeStream(pubkey: pubkey, id: stream.id) }
                }
            }
        }
        
        
        // MARK: - Stream management
        
        private func add(pubkey: Pubkey, stream: ProfileStreamInfo) {
            if self.streams[pubkey] == nil {
                self.streams[pubkey] = [:]
                self.subscriptionNeedsUpdate = true
            }
            self.streams[pubkey]?[stream.id] = stream
        }
        
        func removeStream(pubkey: Pubkey, id: UUID) {
            self.streams[pubkey]?[id] = nil
            if self.streams[pubkey]?.keys.count == 0 {
                // We don't need to subscribe to this profile anymore
                self.streams[pubkey] = nil
                self.subscriptionNeedsUpdate = true
            }
        }
        
        
        // MARK: - Helper types
        
        typealias ProfileStreamItem = NdbTxn<ProfileRecord?>
        
        struct ProfileStreamInfo {
            let id: UUID = UUID()
            let continuation: AsyncStream<ProfileStreamItem>.Continuation
        }
    }
}
