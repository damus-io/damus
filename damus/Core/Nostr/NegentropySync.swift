//
//  NegentropySync.swift
//  damus
//
//  NIP-77 negentropy set reconciliation for efficient timeline sync.
//
//  Instead of re-fetching thousands of events on app foreground, negentropy
//  efficiently identifies only the events we're missing by comparing fingerprints
//  of our local event set against the relay's set. This typically reduces
//  network traffic from 5000+ events to ~50-200 missing events.
//
//  Protocol flow:
//  1. Client sends NEG-OPEN with filter and initial fingerprint
//  2. Relay responds with NEG-MSG containing its fingerprint
//  3. Client/relay exchange NEG-MSG until sets are reconciled
//  4. Client sends NEG-CLOSE, then fetches missing events via REQ
//
//  See: https://github.com/nostr-protocol/nips/blob/master/77.md
//

#if !EXTENSION_TARGET
import Foundation

// MARK: - Types

/// Represents the state of a negentropy sync session
enum NegentropySyncState {
    case idle
    case syncing
    case completed
    case failed(String)
}

/// Result of a negentropy reconciliation
struct NegentropySyncResult {
    /// Event IDs that we have but the relay doesn't (could upload if we wanted)
    let haveIds: [NoteId]
    /// Event IDs that the relay has but we don't (need to fetch)
    let needIds: [NoteId]
    /// Whether the session timed out (vs completed normally)
    let timedOut: Bool

    init(haveIds: [NoteId] = [], needIds: [NoteId] = [], timedOut: Bool = false) {
        self.haveIds = haveIds
        self.needIds = needIds
        self.timedOut = timedOut
    }
}

// MARK: - NegentropySession

/// Manages a single negentropy sync session with one relay.
///
/// Each session handles the multi-round reconciliation protocol:
/// 1. Initialize with local events to build our fingerprint
/// 2. Exchange messages with relay until reconciliation completes
/// 3. Signal completion so caller can fetch missing events
actor NegentropySession {
    let relay: RelayURL
    let filter: NostrFilter
    let subId: String

    private var negentropy: NdbNegentropy?
    private var storage: NdbNegentropyStorage?
    private(set) var state: NegentropySyncState = .idle

    /// Results accumulated across multiple reconciliation rounds
    private var accumulatedHaveIds: [NoteId] = []
    private var accumulatedNeedIds: [NoteId] = []

    /// Continuation for async waiting on session completion
    private var completionContinuation: CheckedContinuation<NegentropySyncResult, Never>?

    init(relay: RelayURL, filter: NostrFilter, subId: String? = nil) {
        self.relay = relay
        self.filter = filter
        self.subId = subId ?? "neg-\(UUID().uuidString.prefix(8))"
    }

    /// Wait for the session to complete and return the results
    func waitForCompletion() async -> NegentropySyncResult {
        // If already completed or failed, return immediately
        switch state {
        case .completed, .failed:
            return NegentropySyncResult(haveIds: accumulatedHaveIds, needIds: accumulatedNeedIds)
        default:
            break
        }

        // Wait for completion signal
        return await withCheckedContinuation { continuation in
            self.completionContinuation = continuation
        }
    }

    /// Signal that the session has completed
    private func signalCompletion() {
        let result = NegentropySyncResult(haveIds: accumulatedHaveIds, needIds: accumulatedNeedIds)
        completionContinuation?.resume(returning: result)
        completionContinuation = nil
    }

    /// Initialize the negentropy session using NostrDB
    /// - Parameters:
    ///   - ndb: NostrDB instance to query local events
    ///   - filter: Filter to query events (should match the sync filter)
    /// - Returns: The initial message to send to the relay (hex-encoded), or nil on failure
    func initiate(with ndb: Ndb, filter: NostrFilter) throws -> String? {
        do {
            // Create storage and populate directly from NostrDB
            storage = try NdbNegentropyStorage()

            // Convert NostrFilter to NdbFilter for the query
            let ndbFilter = try NdbFilter(from: filter)

            // Use a reasonable limit for timeline sync
            let limit = Int32(filter.limit ?? 50_000)

            // Populate storage from NostrDB - this queries LMDB directly
            // without loading full events into memory
            guard let txn = NdbTxn<()>(ndb: ndb) else {
                throw NdbNegentropyError.storageFromFilterFailed
            }
            let count = try storage?.populate(txn: txn, filter: ndbFilter, limit: limit) ?? 0

            Log.debug("Negentropy: populated storage with %d events from NostrDB", for: .networking, count)

            // Create negentropy reconciliation context with conservative settings
            // Relay max message size is ~40KB unsigned
            // Use smaller split_count (4 vs default 16) to reduce response sizes
            guard let storage = storage else { return nil }
            let config = NdbNegentropyConfig(
                frameSizeLimit: 32 * 1024,
                idlistThreshold: 16,
                splitCount: 4  // Fewer splits = smaller responses
            )
            negentropy = try NdbNegentropy(storage: storage, config: config)

            // Generate initial message (hex-encoded for NIP-77)
            let initMessage = try negentropy?.initiateHex()

            state = .syncing
            return initMessage
        } catch {
            Log.error("Failed to initialize negentropy session: %s", for: .networking, error.localizedDescription)
            throw error
        }
    }

    /// Process a NEG-MSG response from the relay
    /// - Parameter messageHex: Hex-encoded negentropy message from relay
    /// - Returns: Next message to send (nil if reconciliation complete), and partial results
    func processMessage(_ messageHex: String) throws -> (nextMessage: String?, haveIds: [NoteId], needIds: [NoteId]) {
        guard let negentropy = negentropy else {
            throw NegentropySyncError.sessionNotFound
        }

        // Process the message and generate response using native implementation
        let nextMsg = try negentropy.reconcileHex(hexMessage: messageHex)

        // Get IDs from the reconciliation - native implementation accumulates them
        let haveNoteIds = negentropy.haveIds
        let needNoteIds = negentropy.needIds

        // Update accumulated results (in case we need them before completion)
        accumulatedHaveIds = haveNoteIds
        accumulatedNeedIds = needNoteIds

        // Empty response means reconciliation is complete
        if nextMsg.isEmpty || negentropy.isComplete {
            state = .completed
            signalCompletion()
            return (nil, haveNoteIds, needNoteIds)
        } else {
            return (nextMsg, haveNoteIds, needNoteIds)
        }
    }

    /// Get the final accumulated results
    func getResults() -> NegentropySyncResult {
        return NegentropySyncResult(haveIds: accumulatedHaveIds, needIds: accumulatedNeedIds)
    }

    /// Mark the session as failed
    func fail(reason: String) {
        state = .failed(reason)
        signalCompletion()
    }
}

/// Error types for negentropy operations
enum NegentropySyncError: Error {
    case invalidMessage
    case sessionNotFound
    case initializationFailed
}

// MARK: - NegentropyManager

/// Tracks an active negentropy fetch subscription for completion logging
struct NegentropyFetchTracker {
    let relay: RelayURL
    let expectedCount: Int
    var receivedCount: Int = 0
}

/// Manages negentropy sync sessions across multiple relays.
///
/// This is the main entry point for negentropy sync. It:
/// - Filters relays by NIP-77 support (via NIP-11)
/// - Runs sync sessions in parallel across relays
/// - Batches event fetches to avoid relay message limits
/// - Tracks fetch completion for logging
actor NegentropyManager {
    private var sessions: [String: NegentropySession] = [:]
    private weak var pool: RelayPool?
    private var ndb: Ndb?
    private var relayModelCache: RelayModelCache?

    /// Tracks active fetch subscriptions by sub_id for completion logging
    private var fetchTrackers: [String: NegentropyFetchTracker] = [:]

    /// Tracks whether a full sync is in progress (to avoid duplicate syncs)
    private var isFullSyncInProgress = false

    /// Tracks which relays have individual syncs in progress
    private var relaySyncsInProgress: Set<RelayURL> = []

    init(pool: RelayPool?, ndb: Ndb?, relayModelCache: RelayModelCache? = nil) {
        self.pool = pool
        self.ndb = ndb
        self.relayModelCache = relayModelCache
    }

    // MARK: Fetch Tracking

    /// Called when an event is received for a negentropy fetch subscription
    func trackFetchedEvent(subId: String) {
        guard var tracker = fetchTrackers[subId] else { return }
        tracker.receivedCount += 1
        fetchTrackers[subId] = tracker
    }

    /// Called when EOSE is received for a negentropy fetch subscription
    func handleFetchEOSE(subId: String) {
        guard let tracker = fetchTrackers.removeValue(forKey: subId) else { return }

        let received = tracker.receivedCount
        let expected = tracker.expectedCount
        let relay = tracker.relay.absoluteString
        let missing = expected - received

        // All events received
        guard missing > 0 else {
            Log.info("Negentropy fetch complete: received %d/%d events from %s",
                    for: .networking, received, expected, relay)
            return
        }

        // Some events missing (relay may not have them, or they were deleted)
        Log.info("Negentropy fetch complete: received %d/%d events from %s (missing %d)",
                for: .networking, received, expected, relay, missing)
    }

    /// Called when relay sends CLOSED for a negentropy fetch subscription (e.g., rate limiting)
    func handleFetchClosed(subId: String, message: String) {
        guard let tracker = fetchTrackers.removeValue(forKey: subId) else { return }

        let received = tracker.receivedCount
        let expected = tracker.expectedCount
        let relay = tracker.relay.absoluteString

        // Rate-limited by relay
        guard !message.hasPrefix("rate-limited:") else {
            Log.info("Negentropy fetch rate-limited: received %d/%d events from %s before limit (%s)",
                    for: .networking, received, expected, relay, message)
            return
        }

        // Other closure reason
        Log.info("Negentropy fetch closed by relay: received %d/%d events from %s (%s)",
                for: .networking, received, expected, relay, message)
    }

    /// Check if a subscription ID is a negentropy fetch
    func isNegentropyFetch(subId: String) -> Bool {
        return fetchTrackers[subId] != nil
    }

    // MARK: NIP-11 Relay Filtering

    /// Check if we have NIP-11 metadata cached for a relay
    @MainActor
    private func hasNIP11Metadata(_ relay: RelayURL, cache: RelayModelCache?) -> Bool {
        guard let cache = cache,
              let model = cache.model(withURL: relay) else {
            return false
        }
        return model.metadata.supported_nips != nil
    }

    /// Check if a relay supports NIP-77 based on its NIP-11 document
    ///
    /// TODO: Some relays (e.g., nos.lol) advertise NIP-77 in their NIP-11 but actually have
    /// negentropy disabled. We should remember when a relay rejects negentropy with
    /// "negentropy disabled" NOTICE and skip it in future sync attempts.
    @MainActor
    private func relaySupportsNIP77(_ relay: RelayURL, cache: RelayModelCache?) -> Bool {
        guard let cache = cache,
              let model = cache.model(withURL: relay),
              let supportedNips = model.metadata.supported_nips else {
            // If we don't have NIP-11 info, don't try negentropy (avoid errors)
            return false
        }
        return supportedNips.contains(77)
    }

    /// Fetch NIP-11 metadata for a relay and check if it supports NIP-77
    /// This is used when metadata isn't cached yet
    private func fetchAndCheckNIP77Support(_ relay: RelayURL, cache: RelayModelCache?) async -> Bool {
        do {
            guard let metadata = try await fetch_relay_metadata(relay_id: relay) else {
                return false
            }

            // Cache the metadata for future use
            if let cache = cache {
                await MainActor.run {
                    let model = RelayModel(relay, metadata: metadata)
                    cache.insert(model: model)
                }
            }

            return metadata.supported_nips?.contains(77) ?? false
        } catch {
            Log.debug("Failed to fetch NIP-11 for %s: %s", for: .networking, relay.absoluteString, error.localizedDescription)
            return false
        }
    }

    // MARK: Sync Entry Point

    /// Start a negentropy sync for a filter across specified relays.
    ///
    /// This is the main entry point. It:
    /// 1. Waits for relay connections (with grace period for slow relays)
    /// 2. Filters to relays that support NIP-77 (via NIP-11)
    /// 3. Runs sync sessions in parallel
    /// 4. Returns aggregated results
    ///
    /// - Parameters:
    ///   - filter: The filter to sync (e.g., timeline events)
    ///   - relays: Specific relays to sync with (nil = all connected relays)
    ///   - relayModelCache: Cache of relay NIP-11 info for filtering by NIP-77 support
    /// - Returns: Dictionary of relay URL to sync results
    func sync(filter: NostrFilter, to relays: [RelayURL]? = nil, relayModelCache: RelayModelCache? = nil) async throws -> [RelayURL: NegentropySyncResult] {
        // Skip if a full sync is already in progress
        guard !isFullSyncInProgress else {
            Log.info("Negentropy sync: skipping, full sync already in progress", for: .networking)
            return [:]
        }

        isFullSyncInProgress = true
        defer { isFullSyncInProgress = false }

        // Use passed cache or fall back to stored one
        let cache = relayModelCache ?? self.relayModelCache
        self.relayModelCache = cache
        guard let pool = pool else {
            throw NegentropySyncError.initializationFailed
        }

        // Wait for relays to connect (up to 5 seconds, with grace period for stragglers)
        var targetRelays: [RelayURL] = []
        var disconnectedRelays: [RelayURL] = []
        var firstConnectionAttempt: Int? = nil

        for attempt in 0..<10 {
            let allRelays = await pool.getRelays(targetRelays: relays)
            targetRelays = allRelays
                .filter { $0.connection.isConnected }
                .map { $0.descriptor.url }
            disconnectedRelays = allRelays
                .filter { !$0.connection.isConnected }
                .map { $0.descriptor.url }

            if !targetRelays.isEmpty {
                // First time we have connections - record it
                if firstConnectionAttempt == nil {
                    firstConnectionAttempt = attempt
                }

                // Wait 2 more attempts (1 second) after first connection for other relays
                // This gives slower relays time to connect
                if attempt >= (firstConnectionAttempt! + 2) || disconnectedRelays.isEmpty {
                    break
                }
            }

            // Wait 500ms before checking again
            try? await Task.sleep(nanoseconds: 500_000_000)
            if targetRelays.isEmpty {
                Log.debug("Negentropy sync: waiting for relay connections (attempt %d)", for: .networking, attempt + 1)
            }
        }

        // Log disconnected relays so user knows why some relays aren't being synced
        if !disconnectedRelays.isEmpty {
            let disconnectedNames = disconnectedRelays.map { $0.absoluteString }.joined(separator: ", ")
            Log.info("Negentropy sync: %d relays not connected: %s", for: .networking, disconnectedRelays.count, disconnectedNames)
        }

        if targetRelays.isEmpty {
            Log.info("Negentropy sync: no connected relays available", for: .networking)
            return [:]
        }

        // Filter to only relays that advertise NIP-77 support in their NIP-11 document
        var nip77Relays: [RelayURL] = []
        var noNip77Relays: [RelayURL] = []
        var uncachedRelays: [RelayURL] = []

        for relay in targetRelays {
            if await relaySupportsNIP77(relay, cache: cache) {
                nip77Relays.append(relay)
            } else if await hasNIP11Metadata(relay, cache: cache) {
                noNip77Relays.append(relay)
            } else {
                uncachedRelays.append(relay)
            }
        }

        // For relays without cached metadata, fetch NIP-11 on-demand (in parallel)
        if !uncachedRelays.isEmpty {
            let uncachedNames = uncachedRelays.map { $0.absoluteString }.joined(separator: ", ")
            Log.info("Negentropy sync: fetching NIP-11 for %d relays: %s", for: .networking, uncachedRelays.count, uncachedNames)

            await withTaskGroup(of: (RelayURL, Bool).self) { group in
                for relay in uncachedRelays {
                    group.addTask {
                        let supportsNIP77 = await self.fetchAndCheckNIP77Support(relay, cache: cache)
                        return (relay, supportsNIP77)
                    }
                }

                for await (relay, supportsNIP77) in group {
                    if supportsNIP77 {
                        nip77Relays.append(relay)
                    } else {
                        noNip77Relays.append(relay)
                    }
                }
            }
        }

        if !noNip77Relays.isEmpty {
            let names = noNip77Relays.map { $0.absoluteString }.joined(separator: ", ")
            Log.info("Negentropy sync: skipping %d relays without NIP-77: %s", for: .networking, noNip77Relays.count, names)
        }

        if nip77Relays.isEmpty {
            Log.info("Negentropy sync: no relays with NIP-77 support found", for: .networking)
            return [:]
        }

        let relayNames = nip77Relays.map { $0.absoluteString }.joined(separator: ", ")
        Log.info("Negentropy sync: starting sync with %d NIP-77 relays: %s", for: .networking, nip77Relays.count, relayNames)

        // Sync with all relays in parallel for speed
        return await withTaskGroup(of: (RelayURL, NegentropySyncResult?).self) { group in
            for relay in nip77Relays {
                group.addTask {
                    do {
                        let result = try await self.syncWithRelay(relay, filter: filter)
                        return (relay, result)
                    } catch {
                        Log.error("Negentropy sync failed for %s: %s", for: .networking, relay.absoluteString, error.localizedDescription)
                        return (relay, nil)
                    }
                }
            }

            var results: [RelayURL: NegentropySyncResult] = [:]
            for await (relay, result) in group {
                if let result = result {
                    results[relay] = result
                }
            }
            return results
        }
    }

    /// Sync a single relay on reconnect.
    ///
    /// Called when a relay reconnects to sync any events we may have missed while disconnected.
    /// Skips if a full sync is in progress (to avoid duplicate work) or if this relay is already syncing.
    /// Skips relays that don't support NIP-77.
    func syncSingleRelay(_ relay: RelayURL) async {
        // Skip if full sync is already in progress (it will handle this relay)
        guard !isFullSyncInProgress else {
            Log.debug("Negentropy reconnect sync: skipping %s, full sync in progress", for: .networking, relay.absoluteString)
            return
        }

        // Skip if this relay is already being synced
        guard !relaySyncsInProgress.contains(relay) else {
            Log.debug("Negentropy reconnect sync: skipping %s, already syncing", for: .networking, relay.absoluteString)
            return
        }

        relaySyncsInProgress.insert(relay)
        defer { relaySyncsInProgress.remove(relay) }

        // Check NIP-77 support
        let supportsNIP77: Bool
        if await relaySupportsNIP77(relay, cache: relayModelCache) {
            supportsNIP77 = true
        } else if await hasNIP11Metadata(relay, cache: relayModelCache) {
            // We have metadata but relay doesn't support NIP-77, skip silently
            return
        } else {
            // No cached metadata, try on-demand fetch
            supportsNIP77 = await fetchAndCheckNIP77Support(relay, cache: relayModelCache)
        }

        guard supportsNIP77 else {
            return
        }

        Log.info("Negentropy sync: reconnected relay %s, starting sync", for: .networking, relay.absoluteString)

        // Build filter for timeline events (same as app foreground sync)
        // Note: limit is required for relay.damus.io NEG-OPEN
        var filter = NostrFilter(kinds: [.text, .longform, .highlight])
        filter.limit = 50000

        do {
            let result = try await syncWithRelay(relay, filter: filter)

            // If timed out, the error was already logged in syncWithRelay
            guard !result.timedOut else {
                return
            }

            // Log result - fetching is already handled by handleNegentropyMessage
            if result.needIds.isEmpty {
                Log.info("Negentropy reconnect sync: %s - already up to date", for: .networking, relay.absoluteString)
            }
            // Note: if needIds is not empty, the fetch log is already shown by fetchMissingEvents
        } catch {
            Log.error("Negentropy reconnect sync failed for %s: %s",
                     for: .networking, relay.absoluteString, error.localizedDescription)
        }
    }

    // MARK: Single Relay Sync (Private)

    /// Sync with a single relay.
    ///
    /// Creates a session, sends NEG-OPEN, waits for completion (with timeout),
    /// then fetches missing events.
    private func syncWithRelay(_ relay: RelayURL, filter: NostrFilter) async throws -> NegentropySyncResult {
        guard let ndb = ndb else {
            throw NegentropySyncError.initializationFailed
        }

        let session = NegentropySession(relay: relay, filter: filter)
        let subId = await session.subId
        sessions[subId] = session

        defer {
            sessions.removeValue(forKey: subId)
        }

        // Initialize with NostrDB - this populates storage directly from LMDB
        // without loading full events into memory
        guard let initialMessage = try await session.initiate(with: ndb, filter: filter) else {
            throw NegentropySyncError.initializationFailed
        }

        // Send NEG-OPEN
        let negOpen = NegentropyOpen(sub_id: subId, filter: filter, initial_message: initialMessage)
        Log.info("Negentropy: sending NEG-OPEN to %s (msg size: %d bytes)",
                for: .networking, relay.absoluteString, initialMessage.count / 2)  // hex = 2 chars per byte
        await pool?.send(.negOpen(negOpen), to: [relay])

        // Wait for completion with a timeout of 30 seconds
        // The session will be signaled complete when handleNegentropyMessage receives the final response
        // or when handleNegentropyError is called
        return await withTaskGroup(of: NegentropySyncResult.self) { group in
            // Task 1: Wait for actual completion
            group.addTask {
                await session.waitForCompletion()
            }

            // Task 2: Timeout after 30 seconds
            group.addTask {
                do {
                    try await Task.sleep(nanoseconds: 30_000_000_000)
                    // Only reaches here if not cancelled - actual timeout
                    Log.error("Negentropy: timeout waiting for %s", for: .networking, relay.absoluteString)
                    await session.fail(reason: "Timeout waiting for relay response")
                    let result = await session.getResults()
                    return NegentropySyncResult(haveIds: result.haveIds, needIds: result.needIds, timedOut: true)
                } catch {
                    // Task was cancelled (session completed first) - return dummy result
                    return NegentropySyncResult()
                }
            }

            // Return the first result (either completion or timeout)
            let result = await group.next() ?? NegentropySyncResult(timedOut: true)
            group.cancelAll()
            return result
        }
    }

    // MARK: Message Handlers

    /// Handle a NEG-MSG response from a relay.
    ///
    /// Continues the reconciliation by processing the message and either:
    /// - Sending another NEG-MSG if more rounds needed
    /// - Fetching missing events and closing if complete
    func handleNegentropyMessage(_ response: NegentropyResponse, from relay: RelayURL) async {
        guard let session = sessions[response.sub_id] else {
            Log.error("Received NEG-MSG for unknown session: %s", for: .networking, response.sub_id)
            return
        }

        Log.debug("Negentropy: received NEG-MSG from %s", for: .networking, relay.absoluteString)

        do {
            let (nextMessage, _, _) = try await session.processMessage(response.message)

            if let nextMessage = nextMessage {
                // Continue reconciliation
                Log.debug("Negentropy: continuing reconciliation with %s", for: .networking, relay.absoluteString)
                let negMsg = NegentropyMessage(sub_id: response.sub_id, message: nextMessage)
                await pool?.send(.negMsg(negMsg), to: [relay])
            } else {
                // Reconciliation complete, fetch missing events
                let results = await session.getResults()
                Log.debug("Negentropy: reconciliation complete for %s, need %d events", for: .networking, relay.absoluteString, results.needIds.count)
                await fetchMissingEvents(results.needIds, from: relay)

                // Close the negentropy session
                let negClose = NegentropyClose(sub_id: response.sub_id)
                await pool?.send(.negClose(negClose), to: [relay])
            }
        } catch {
            Log.error("Failed to process NEG-MSG: %s", for: .networking, error.localizedDescription)
            await session.fail(reason: error.localizedDescription)
        }
    }

    /// Handle a NEG-ERR response from a relay
    func handleNegentropyError(_ error: NegentropyError) async {
        guard let session = sessions[error.sub_id] else {
            return
        }
        await session.fail(reason: error.reason)
        sessions.removeValue(forKey: error.sub_id)
    }

    // MARK: Helpers

    /// Maximum IDs per fetch request to stay under relay message size limits.
    /// At ~68 bytes per hex ID, 500 IDs ≈ 34KB, safely under the ~40KB typical limit.
    private static let maxIdsPerFetch = 500

    /// Fetch missing events from a relay in batches.
    ///
    /// Large ID lists are split into batches to avoid relay message size limits.
    /// Each batch gets its own subscription for tracking completion.
    private func fetchMissingEvents(_ eventIds: [NoteId], from relay: RelayURL) async {
        guard !eventIds.isEmpty else {
            Log.info("Negentropy: %s - already up to date", for: .networking, relay.absoluteString)
            return
        }

        // Split into batches to stay under relay message size limits
        let batches = eventIds.chunked(into: Self.maxIdsPerFetch)

        Log.info("Negentropy: requesting %d events in %d batches from %s",
                for: .networking, eventIds.count, batches.count, relay.absoluteString)

        for (index, batch) in batches.enumerated() {
            var filter = NostrFilter()
            filter.ids = batch

            let subId = "neg-fetch-\(UUID().uuidString.prefix(8))"

            // Track this fetch so we can log when it completes
            fetchTrackers[subId] = NegentropyFetchTracker(relay: relay, expectedCount: batch.count)

            let sub = NostrSubscribe(filters: [filter], sub_id: subId)
            await pool?.send(.subscribe(sub), to: [relay])

            // Small delay between batches to avoid overwhelming the relay
            if index < batches.count - 1 {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            }
        }
    }
}

// Note: hex_encode and hex_decode are defined in ProofOfWork.swift

#endif  // !EXTENSION_TARGET
