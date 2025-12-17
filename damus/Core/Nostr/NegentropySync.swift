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

// MARK: - Negentropy Support Cache

/// Caches which relays support negentropy to avoid repeated checks.
/// Results are cached for 7 days to allow relays to update their support.
final class NegentropySupportCache {
    private static let cacheKey = "negentropy_relay_support_cache"

    /// Cached result for a relay
    struct CacheEntry: Codable {
        let supported: Bool
        let timestamp: Date

        var isExpired: Bool {
            Date().timeIntervalSince(timestamp) > Self.cacheExpiryDays * 24 * 60 * 60
        }

        private static let cacheExpiryDays = 7.0
    }

    private var cache: [String: CacheEntry] = [:]

    init() {
        loadFromUserDefaults()
    }

    /// Check if a relay is known to support negentropy
    func isKnownSupported(_ relay: RelayURL) -> Bool {
        guard let entry = cache[relay.absoluteString] else {
            return false  // Unknown
        }
        if entry.isExpired {
            cache.removeValue(forKey: relay.absoluteString)
            return false  // Expired
        }
        return entry.supported
    }

    /// Check if a relay is known to NOT support negentropy
    func isKnownUnsupported(_ relay: RelayURL) -> Bool {
        guard let entry = cache[relay.absoluteString] else {
            return false  // Unknown
        }
        if entry.isExpired {
            cache.removeValue(forKey: relay.absoluteString)
            return false  // Expired
        }
        return !entry.supported
    }

    /// Check if a relay's support status is unknown (not in cache)
    func isUnknown(_ relay: RelayURL) -> Bool {
        guard let entry = cache[relay.absoluteString] else {
            return true  // Not in cache
        }
        if entry.isExpired {
            cache.removeValue(forKey: relay.absoluteString)
            return true  // Expired = unknown
        }
        return false
    }

    /// Mark a relay as supporting or not supporting negentropy
    func setSupport(_ relay: RelayURL, supported: Bool) {
        cache[relay.absoluteString] = CacheEntry(supported: supported, timestamp: Date())
        saveToUserDefaults()
    }

    /// Get all relays known to support negentropy
    func knownSupportedRelays() -> [String] {
        return cache.filter { !$0.value.isExpired && $0.value.supported }.map { $0.key }
    }

    private func loadFromUserDefaults() {
        guard let data = UserDefaults.standard.data(forKey: Self.cacheKey),
              let decoded = try? JSONDecoder().decode([String: CacheEntry].self, from: data) else {
            return
        }
        // Filter out expired entries on load
        cache = decoded.filter { !$0.value.isExpired }
    }

    private func saveToUserDefaults() {
        guard let data = try? JSONEncoder().encode(cache) else { return }
        UserDefaults.standard.set(data, forKey: Self.cacheKey)
    }
}

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

    /// Tracks when we last received a message (for inactivity timeout)
    private(set) var lastActivityTime: Date = Date()

    /// Whether we've received at least one response (confirms relay supports negentropy)
    private(set) var hasReceivedResponse: Bool = false

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

        // Track activity for timeout management
        hasReceivedResponse = true
        lastActivityTime = Date()

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

    /// Tracks active fetch subscriptions by sub_id for completion logging
    private var fetchTrackers: [String: NegentropyFetchTracker] = [:]

    /// Tracks whether a full sync is in progress (to avoid duplicate syncs)
    private var isFullSyncInProgress = false

    /// Tracks which relays have individual syncs in progress
    private var relaySyncsInProgress: Set<RelayURL> = []

    /// Cache for relay negentropy support (avoids NIP-11 checks on every startup)
    private let supportCache = NegentropySupportCache()

    init(pool: RelayPool?, ndb: Ndb?) {
        self.pool = pool
        self.ndb = ndb
    }

    /// Mark a relay as not supporting negentropy (called when we get NEG-ERR or "negentropy disabled")
    /// Also cancels any pending sessions for this relay.
    func markRelayUnsupported(_ relay: RelayURL) {
        supportCache.setSupport(relay, supported: false)

        // Cancel any pending sessions for this relay
        for (subId, session) in sessions {
            Task {
                let sessionRelay = await session.relay
                if sessionRelay == relay {
                    await session.fail(reason: "Relay does not support negentropy")
                    sessions.removeValue(forKey: subId)
                }
            }
        }

        // Remove from in-progress tracking
        relaySyncsInProgress.remove(relay)
    }

    /// Mark a relay as supporting negentropy (called when we get a successful NEG-MSG)
    func markRelaySupported(_ relay: RelayURL) {
        supportCache.setSupport(relay, supported: true)
    }

    /// Check if relay support status is unknown
    func isRelayUnknown(_ relay: RelayURL) -> Bool {
        return supportCache.isUnknown(relay)
    }

    // MARK: NIP-11 Background Check

    /// Check NIP-11 for unknown relays and sync those that support NIP-77.
    /// This runs in the background and doesn't block startup.
    private func checkNIP11AndSyncIfSupported(_ relays: [RelayURL], filter: NostrFilter) async {
        await withTaskGroup(of: Void.self) { group in
            for relay in relays {
                group.addTask {
                    do {
                        // Fetch NIP-11 metadata
                        guard let metadata = try await fetch_relay_metadata(relay_id: relay) else {
                            Log.debug("Negentropy: no NIP-11 metadata for %s", for: .networking, relay.absoluteString)
                            return
                        }

                        // Check if relay advertises NIP-77 support
                        let supportsNIP77 = metadata.supported_nips?.contains(77) ?? false

                        if supportsNIP77 {
                            Log.info("Negentropy: %s advertises NIP-77, starting sync", for: .networking, relay.absoluteString)
                            // Mark as potentially supported and try to sync
                            // (will be confirmed as supported when we get NEG-MSG)
                            await self.syncSingleRelayInternal(relay, filter: filter)
                        } else {
                            // Mark as unsupported so we don't check again
                            await self.markRelayUnsupported(relay)
                            Log.debug("Negentropy: %s does not advertise NIP-77", for: .networking, relay.absoluteString)
                        }
                    } catch {
                        Log.debug("Negentropy: failed to fetch NIP-11 for %s: %s",
                                 for: .networking, relay.absoluteString, error.localizedDescription)
                    }
                }
            }
        }
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

    // MARK: Sync Entry Point

    /// Start a negentropy sync for a filter across specified relays.
    ///
    /// This is the main entry point. It:
    /// 1. Waits for relay connections (with grace period for slow relays)
    /// 2. Tries all relays optimistically (skips those cached as unsupported)
    /// 3. Runs sync sessions in parallel
    /// 4. Caches relay support based on responses (NEG-MSG = supported, NEG-ERR = unsupported)
    ///
    /// - Parameters:
    ///   - filter: The filter to sync (e.g., timeline events)
    ///   - relays: Specific relays to sync with (nil = all connected relays)
    /// - Returns: Dictionary of relay URL to sync results
    func sync(filter: NostrFilter, to relays: [RelayURL]? = nil) async throws -> [RelayURL: NegentropySyncResult] {
        // Skip if a full sync is already in progress
        guard !isFullSyncInProgress else {
            Log.info("Negentropy sync: skipping, full sync already in progress", for: .networking)
            return [:]
        }

        isFullSyncInProgress = true
        defer { isFullSyncInProgress = false }

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

        // Only sync relays we KNOW support negentropy (from cache).
        // Unknown relays will be checked via NIP-11 in the background.
        // Skip relays that are already syncing (from connect handler).
        var syncRelays: [RelayURL] = []
        var skippedRelays: [RelayURL] = []
        var unknownRelays: [RelayURL] = []
        var alreadySyncing: [RelayURL] = []

        for relay in targetRelays {
            if relaySyncsInProgress.contains(relay) {
                alreadySyncing.append(relay)
            } else if supportCache.isKnownSupported(relay) {
                syncRelays.append(relay)
            } else if supportCache.isKnownUnsupported(relay) {
                skippedRelays.append(relay)
            } else {
                unknownRelays.append(relay)
            }
        }

        if !alreadySyncing.isEmpty {
            let names = alreadySyncing.map { $0.absoluteString }.joined(separator: ", ")
            Log.debug("Negentropy sync: %d relays already syncing: %s", for: .networking, alreadySyncing.count, names)
        }

        if !skippedRelays.isEmpty {
            let names = skippedRelays.map { $0.absoluteString }.joined(separator: ", ")
            Log.info("Negentropy sync: skipping %d relays (cached as unsupported): %s", for: .networking, skippedRelays.count, names)
        }

        // Check NIP-11 for unknown relays in the background (doesn't block startup)
        if !unknownRelays.isEmpty {
            let names = unknownRelays.map { $0.absoluteString }.joined(separator: ", ")
            Log.info("Negentropy sync: checking NIP-11 for %d unknown relays in background: %s", for: .networking, unknownRelays.count, names)
            Task {
                await self.checkNIP11AndSyncIfSupported(unknownRelays, filter: filter)
            }
        }

        if syncRelays.isEmpty {
            Log.info("Negentropy sync: no known-supported relays to sync immediately", for: .networking)
            return [:]
        }

        // Short settling delay to let connections fully establish
        // WebSocket "connected" doesn't mean the relay is ready to process messages.
        // The NIP-11 check (for unknown relays) provides this delay naturally.
        try? await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5 seconds

        let relayNames = syncRelays.map { $0.absoluteString }.joined(separator: ", ")
        Log.info("Negentropy sync: starting sync with %d relays: %s", for: .networking, syncRelays.count, relayNames)

        // Track all relays we're about to sync to prevent duplicate reconnect syncs
        for relay in syncRelays {
            relaySyncsInProgress.insert(relay)
        }

        // Sync with all relays in parallel for speed
        let results = await withTaskGroup(of: (RelayURL, NegentropySyncResult?).self) { group in
            for relay in syncRelays {
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

        // Clear tracking for completed syncs
        for relay in syncRelays {
            relaySyncsInProgress.remove(relay)
        }

        return results
    }

    /// Sync a single relay on connect/reconnect.
    ///
    /// Called when a relay connects to sync any events we may have missed.
    /// - Known supported: syncs immediately
    /// - Known unsupported: skips
    /// - Unknown: checks NIP-11 first, then syncs if supported
    func syncSingleRelay(_ relay: RelayURL) async {
        // Skip if this relay is already being synced
        guard !relaySyncsInProgress.contains(relay) else {
            Log.debug("Negentropy reconnect sync: skipping %s, already syncing", for: .networking, relay.absoluteString)
            return
        }

        // Skip if we know this relay doesn't support negentropy
        guard !supportCache.isKnownUnsupported(relay) else {
            return
        }

        // Build filter for timeline events
        var filter = NostrFilter(kinds: [.text, .longform, .highlight])
        filter.limit = 50000

        // If relay is known supported, sync after short settling delay
        if supportCache.isKnownSupported(relay) {
            Log.info("Negentropy sync: relay %s reconnected, waiting for connection to settle", for: .networking, relay.absoluteString)
            // Short delay to let reconnection fully establish
            try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second
            await syncSingleRelayInternal(relay, filter: filter)
            return
        }

        // Unknown relay - check NIP-11 first (in background to not block)
        Log.debug("Negentropy sync: checking NIP-11 for unknown relay %s", for: .networking, relay.absoluteString)
        Task {
            do {
                guard let metadata = try await fetch_relay_metadata(relay_id: relay) else {
                    Log.debug("Negentropy: no NIP-11 metadata for %s", for: .networking, relay.absoluteString)
                    return
                }

                let supportsNIP77 = metadata.supported_nips?.contains(77) ?? false

                if supportsNIP77 {
                    Log.info("Negentropy: %s advertises NIP-77, starting sync", for: .networking, relay.absoluteString)
                    await self.syncSingleRelayInternal(relay, filter: filter)
                } else {
                    await self.markRelayUnsupported(relay)
                    Log.debug("Negentropy: %s does not advertise NIP-77", for: .networking, relay.absoluteString)
                }
            } catch {
                Log.debug("Negentropy: failed to fetch NIP-11 for %s: %s",
                         for: .networking, relay.absoluteString, error.localizedDescription)
            }
        }
    }

    /// Internal method to sync a single relay (assumes checks already done).
    private func syncSingleRelayInternal(_ relay: RelayURL, filter: NostrFilter) async {
        // Skip if this relay is already being synced
        guard !relaySyncsInProgress.contains(relay) else {
            Log.debug("Negentropy sync: skipping %s, already syncing", for: .networking, relay.absoluteString)
            return
        }

        relaySyncsInProgress.insert(relay)
        defer { relaySyncsInProgress.remove(relay) }

        do {
            let result = try await syncWithRelay(relay, filter: filter)

            // If timed out, the error was already logged in syncWithRelay
            guard !result.timedOut else {
                return
            }

            // Log result - fetching is already handled by handleNegentropyMessage
            if result.needIds.isEmpty {
                Log.info("Negentropy sync: %s - already up to date", for: .networking, relay.absoluteString)
            }
        } catch {
            Log.error("Negentropy sync failed for %s: %s",
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

        // Two-phase timeout:
        // - First response: 10s (fail fast if relay doesn't support NIP-77)
        // - After first response: 30s inactivity timeout (give time for multi-round reconciliation)
        return await withTaskGroup(of: NegentropySyncResult.self) { group in
            // Task 1: Wait for actual completion
            group.addTask {
                await session.waitForCompletion()
            }

            // Task 2: Inactivity-based timeout
            group.addTask {
                let startTime = Date()
                let initialTimeout: TimeInterval = 10  // 10s for first response
                let inactivityTimeout: TimeInterval = 30  // 30s between messages

                while true {
                    do {
                        // Check every 2 seconds
                        try await Task.sleep(nanoseconds: 2_000_000_000)

                        let hasResponse = await session.hasReceivedResponse
                        let lastActivity = await session.lastActivityTime

                        if !hasResponse {
                            // Still waiting for first response
                            if Date().timeIntervalSince(startTime) > initialTimeout {
                                Log.info("Negentropy: timeout waiting for %s (may not support NIP-77)", for: .networking, relay.absoluteString)
                                await session.fail(reason: "Timeout waiting for first response")
                                let result = await session.getResults()
                                return NegentropySyncResult(haveIds: result.haveIds, needIds: result.needIds, timedOut: true)
                            }
                        } else {
                            // Have received response, check for inactivity
                            if Date().timeIntervalSince(lastActivity) > inactivityTimeout {
                                Log.info("Negentropy: inactivity timeout for %s", for: .networking, relay.absoluteString)
                                await session.fail(reason: "Inactivity timeout")
                                let result = await session.getResults()
                                return NegentropySyncResult(haveIds: result.haveIds, needIds: result.needIds, timedOut: true)
                            }
                        }
                    } catch {
                        // Task was cancelled (session completed first) - return dummy result
                        return NegentropySyncResult()
                    }
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

        // First successful NEG-MSG confirms this relay supports negentropy
        markRelaySupported(relay)

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

    /// Handle a NEG-ERR response from a relay.
    ///
    /// Marks the relay as not supporting negentropy in the cache so we skip it in future syncs.
    func handleNegentropyError(_ error: NegentropyError) async {
        guard let session = sessions[error.sub_id] else {
            return
        }

        // Cache this relay as unsupported so we don't try again
        let relay = await session.relay
        markRelayUnsupported(relay)
        Log.info("Negentropy: marking %s as unsupported (NEG-ERR: %s)",
                for: .networking, relay.absoluteString, error.reason)

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
