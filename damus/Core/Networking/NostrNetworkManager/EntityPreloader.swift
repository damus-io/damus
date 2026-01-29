//
//  EntityPreloader.swift
//  damus
//
//  Created by Daniel D'Aquino on 2026-01-22.
//

import Foundation
import os
import Negentropy

extension NostrNetworkManager {
    /// Preloads entities referenced in notes to improve user experience.
    ///
    /// This actor efficiently batches entity preload requests to avoid overloading the network.
    /// Currently limited to preloading profile metadata, but designed to be expanded to other
    /// entity types (e.g., referenced events, media) in the future.
    ///
    /// ## Implementation notes
    ///
    /// - Uses a queue to collect preload requests
    /// - Batches requests intelligently: either when 500 pending requests accumulate, or after 1 second
    /// - Uses standard Nostr subscriptions to fetch metadata
    /// - Runs a long-running task to process the queue continuously
    actor EntityPreloader {
        private let pool: RelayPool
        private let ndb: Ndb
        private let queue: QueueableNotify<Set<Pubkey>>
        private var processingTask: Task<Void, Never>?
        private var accumulatedPubkeys = Set<Pubkey>()
        
        private static let logger = Logger(
            subsystem: Constants.MAIN_APP_BUNDLE_IDENTIFIER,
            category: "entity_preloader"
        )
        
        /// Maximum number of items allowed in the queue before old items are discarded
        private static let maxQueueItems = 1000
        /// Batch size threshold - preload immediately when this many requests are pending
        private static let batchSizeThreshold = 500
        /// Time threshold - preload after this duration even if batch size not reached
        private static let timeThreshold: Duration = .seconds(1)
        
        init(pool: RelayPool, ndb: Ndb) {
            self.pool = pool
            self.ndb = ndb
            self.queue = QueueableNotify<Set<Pubkey>>(maxQueueItems: Self.maxQueueItems)
        }
        
        /// Starts the preloader's background processing task
        func start() {
            guard processingTask == nil else {
                Self.logger.warning("EntityPreloader already started")
                return
            }
            
            Self.logger.info("Starting EntityPreloader")
            processingTask = Task {
                await monitorQueue()
            }
        }
        
        /// Stops the preloader's background processing task
        func stop() {
            Self.logger.info("Stopping EntityPreloader")
            processingTask?.cancel()
            processingTask = nil
        }
        
        /// Preloads metadata for the author and referenced profiles in a note
        ///
        /// - Parameter noteLender: The note to extract profiles from
        nonisolated func preload(note noteLender: NdbNoteLender) {
            Task {
                do {
                    let pubkeys = try noteLender.borrow { event in
                        if event.known_kind == .metadata { return Set<Pubkey>() }  // Don't preload pubkeys from a user profile
                        var pubkeys = Set<Pubkey>()
                        
                        // Add the author
                        pubkeys.insert(event.pubkey)
                        
                        // Add all referenced pubkeys from p tags
                        for referencedPubkey in event.referenced_pubkeys {
                            pubkeys.insert(referencedPubkey)
                        }
                        
                        return pubkeys
                    }
                    
                    guard !pubkeys.isEmpty else { return }
                    
                    // Filter out pubkeys that already have profiles in ndb
                    let pubkeysToPreload = await pubkeys.asyncFilter { pubkey in
                        let hasProfile = (try? await ndb.lookup_profile(pubkey, borrow: { pr in
                            pr != nil
                        })) ?? false
                        return !hasProfile
                    }
                    
                    guard !pubkeysToPreload.isEmpty else {
                        Self.logger.debug("All \(pubkeys.count, privacy: .public) profiles already in ndb, skipping preload")
                        return
                    }
                    
                    Self.logger.debug("Queueing preload for \(pubkeysToPreload.count, privacy: .public) profiles (\(pubkeys.count - pubkeysToPreload.count, privacy: .public) already cached)")
                    await queue.add(item: pubkeysToPreload)
                } catch {
                    Self.logger.error("Error extracting pubkeys from note: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
        
        /// Processes the queue continuously, batching requests intelligently
        private func monitorQueue() async {
            await withThrowingTaskGroup { group in
                group.addTask {
                    for await newPubkeys in await self.queue.stream {
                        try Task.checkCancellation()
                        await self.handle(newQueueItem: newPubkeys)
                    }
                }
                
                group.addTask {
                    while !Task.isCancelled {
                        try await Task.sleep(for: Self.timeThreshold)
                        await self.handleTimerTick()
                    }
                }
            }
        }
        
        private func handleTimerTick() async {
            if accumulatedPubkeys.count > 0 {
                await self.performPreload()
            }
        }
        
        private func handle(newQueueItem: Set<Pubkey>) async {
            accumulatedPubkeys = self.accumulatedPubkeys.union(newQueueItem)
            if accumulatedPubkeys.count > Self.batchSizeThreshold {
                await self.performPreload()
            }
        }
        
        private func performPreload() async {
            let pubkeysToPreload = accumulatedPubkeys
            accumulatedPubkeys.removeAll()
            Self.logger.debug("Preloading \(pubkeysToPreload.count, privacy: .public) profiles")
            await self.performPreload(pubkeys: pubkeysToPreload)
        }
        
        /// Performs the actual preload operation using standard Nostr subscriptions.
        ///
        /// - Parameter pubkeys: The set of pubkeys to preload metadata for
        private func performPreload(pubkeys: Set<Pubkey>) async {
            guard !pubkeys.isEmpty else { return }
            
            print("EntityPreloader.performPreload: Starting preload for \(pubkeys.count) pubkeys")
            
            let filter = NostrFilter(
                kinds: [.metadata],
                authors: Array(pubkeys)
            )
            
            for try await _ in await pool.subscribeExistingItems(
                filters: [filter],
                to: nil,
                eoseTimeout: .seconds(10),
            ) {
                // NO-OP: We are only subscribing to let nostrdb ingest those events, but we do not need special handling here.
                guard !Task.isCancelled else { break }
            }
            
            Self.logger.debug("Completed metadata fetch for \(pubkeys.count, privacy: .public) profiles")
        }
    }
}

// MARK: - Private Extensions

private extension Set {
    /// Asynchronously filters the set based on an async predicate
    ///
    /// - Parameter predicate: An async closure that returns true for elements to include
    /// - Returns: A new set containing only elements for which predicate returns true
    func asyncFilter(_ predicate: (Element) async -> Bool) async -> Set<Element> {
        var result = Set<Element>()
        for element in self {
            if await predicate(element) {
                result.insert(element)
            }
        }
        return result
    }
}
