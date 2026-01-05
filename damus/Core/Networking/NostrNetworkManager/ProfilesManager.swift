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
            let startTime = CFAbsoluteTimeGetCurrent()
            print("DIAG[\(startTime)] ProfilesManager.stop: START")
            await withTaskGroup { group in
                // Spawn each cancellation in parallel for better execution speed
                group.addTask {
                    print("DIAG[\(startTime)] ProfilesManager.stop: subscriptionSwitcherTask.cancel START")
                    await self.subscriptionSwitcherTask?.cancel()
                    try? await self.subscriptionSwitcherTask?.value
                    print("DIAG[\(startTime)] ProfilesManager.stop: subscriptionSwitcherTask.cancel END")
                }
                group.addTask {
                    print("DIAG[\(startTime)] ProfilesManager.stop: profileListenerTask.cancel START")
                    await self.profileListenerTask?.cancel()
                    try? await self.profileListenerTask?.value
                    print("DIAG[\(startTime)] ProfilesManager.stop: profileListenerTask.cancel END")
                }
                // But await for all of them to be done before returning to avoid race conditions
                for await value in group { continue }
            }
            print("DIAG[\(startTime)] ProfilesManager.stop: END")
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
            try? ndb.write_profile_last_fetched(pubkey: metadataEvent.pubkey, fetched_at: now)
            
            if let relevantStreams = streams[metadataEvent.pubkey] {
                // If we have the user metadata event in ndb, then we should have the profile record as well.
                guard let profile = try? ndb.lookup_profile_and_copy(metadataEvent.pubkey) else { return }
                for relevantStream in relevantStreams.values {
                    relevantStream.continuation.yield(profile)
                }
            }
        }
        
        /// Manually trigger profile updates for a given pubkey
        /// This is useful for local profile changes (e.g., nip05 validation, donation percentage updates)
        func notifyProfileUpdate(pubkey: Pubkey) {
            if let relevantStreams = streams[pubkey] {
                guard let profile = try? ndb.lookup_profile_and_copy(pubkey) else { return }
                for relevantStream in relevantStreams.values {
                    relevantStream.continuation.yield(profile)
                }
            }
        }
        
        
        // MARK: - Streaming interface

        /// Streams profile updates for a single pubkey.
        ///
        /// By default, the stream immediately yields the existing profile from NostrDB
        /// (if available), then continues yielding updates as they arrive from the network.
        ///
        /// This immediate yield is essential for views that display profile data (names,
        /// pictures) because the subscription restart has a ~1 second delay. Without it,
        /// views would flash abbreviated pubkeys or robohash placeholders.
        ///
        /// Set `yieldCached: false` for subscribers that only need network updates (e.g.,
        /// re-rendering content when profiles change) and already handle initial state
        /// through other means.
        ///
        /// - Parameters:
        ///   - pubkey: The pubkey to stream profile updates for
        ///   - yieldCached: Whether to immediately yield the cached profile. Defaults to `true`.
        /// - Returns: An AsyncStream that yields Profile objects
        func streamProfile(pubkey: Pubkey, yieldCached: Bool = true) -> AsyncStream<ProfileStreamItem> {
            return AsyncStream<ProfileStreamItem> { continuation in
                let stream = ProfileStreamInfo(continuation: continuation)
                self.add(pubkey: pubkey, stream: stream)

                // Yield cached profile immediately so views don't flash placeholder content.
                // Callers that only need updates (not initial state) can opt out via yieldCached: false.
                if yieldCached, let existingProfile = try? ndb.lookup_profile_and_copy(pubkey) {
                    continuation.yield(existingProfile)
                }

                continuation.onTermination = { @Sendable _ in
                    Task { await self.removeStream(pubkey: pubkey, id: stream.id) }
                }
            }
        }

        /// Streams profile updates for multiple pubkeys.
        ///
        /// Same behavior as `streamProfile(_:yieldCached:)` but for a set of pubkeys.
        ///
        /// - Parameters:
        ///   - pubkeys: The set of pubkeys to stream profile updates for
        ///   - yieldCached: Whether to immediately yield cached profiles. Defaults to `true`.
        /// - Returns: An AsyncStream that yields Profile objects
        func streamProfiles(pubkeys: Set<Pubkey>, yieldCached: Bool = true) -> AsyncStream<ProfileStreamItem> {
            guard !pubkeys.isEmpty else {
                return AsyncStream<ProfileStreamItem> { continuation in
                    continuation.finish()
                }
            }

            return AsyncStream<ProfileStreamItem> { continuation in
                let stream = ProfileStreamInfo(continuation: continuation)
                for pubkey in pubkeys {
                    self.add(pubkey: pubkey, stream: stream)
                }

                // Yield cached profiles immediately so views render correctly from the start.
                // Callers that only need updates (not initial state) can opt out via yieldCached: false.
                if yieldCached {
                    for pubkey in pubkeys {
                        if let existingProfile = try? ndb.lookup_profile_and_copy(pubkey) {
                            continuation.yield(existingProfile)
                        }
                    }
                }

                continuation.onTermination = { @Sendable _ in
                    Task {
                        for pubkey in pubkeys {
                            await self.removeStream(pubkey: pubkey, id: stream.id)
                        }
                    }
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
        
        typealias ProfileStreamItem = Profile
        
        struct ProfileStreamInfo {
            let id: UUID = UUID()
            let continuation: AsyncStream<ProfileStreamItem>.Continuation
        }
    }
}
