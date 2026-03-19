//
//  PostBox.swift
//  damus
//
//  Created by William Casarin on 2023-03-20.
//

import Foundation


class Relayer {
    let relay: RelayURL
    var attempts: Int
    var retry_after: Double
    var last_attempt: Int64?

    init(relay: RelayURL, attempts: Int, retry_after: Double) {
        self.relay = relay
        self.attempts = attempts
        self.retry_after = retry_after
        self.last_attempt = nil
    }
}

enum OnFlush {
    case once((PostedEvent) -> Void)
    case all((PostedEvent) -> Void)
}

class PostedEvent {
    let event: NostrEvent
    let skip_ephemeral: Bool
    var remaining: [Relayer]
    let flush_after: Date?
    var flushed_once: Bool
    let on_flush: OnFlush?
    let is_targeted: Bool
    /// Whether inbox delivery has been evaluated for this event.
    /// Set on first flush before guards run — does not imply a task was actually spawned
    /// (targeted sends, events without p-tags, and nil-ndb paths all exit early).
    var inboxDeliveryEvaluated: Bool = false

    init(event: NostrEvent, remaining: [RelayURL], skip_ephemeral: Bool, flush_after: Date?, on_flush: OnFlush?, is_targeted: Bool = false) {
        self.event = event
        self.skip_ephemeral = skip_ephemeral
        self.flush_after = flush_after
        self.on_flush = on_flush
        self.is_targeted = is_targeted
        self.flushed_once = false
        self.remaining = remaining.map {
            Relayer(relay: $0, attempts: 0, retry_after: 10.0)
        }
    }
}

enum CancelSendErr {
    case nothing_to_cancel
    case not_delayed
    case too_late
}

actor PostBox {
    private let pool: RelayPool
    private let ndb: Ndb?
    var events: [NoteId: PostedEvent]

    init(pool: RelayPool, ndb: Ndb? = nil) {
        self.pool = pool
        self.ndb = ndb
        self.events = [:]
        Task {
            let stream = AsyncStream<(RelayURL, NostrConnectionEvent)> { streamContinuation in
                Task { await self.pool.register_handler(sub_id: "postbox", filters: nil, to: nil, handler: streamContinuation) }
            }
            for await (relayUrl, connectionEvent) in stream {
                await handle_event(relay_id: relayUrl, connectionEvent)
            }
        }
    }
    
    // only works reliably on delay-sent events
    func cancel_send(evid: NoteId) -> CancelSendErr? {
        guard let ev = events[evid] else {
            return .nothing_to_cancel
        }
        
        guard let after = ev.flush_after else {
            return .not_delayed
        }
        
        guard Date.now < after else {
            return .too_late
        }
        
        events.removeValue(forKey: evid)
        return nil
    }
    
    func try_flushing_events() async {
        let now = Int64(Date().timeIntervalSince1970)
        for kv in events {
            let event = kv.value
            
            // some are delayed
            if let after = event.flush_after, Date.now.timeIntervalSince1970 < after.timeIntervalSince1970 {
                continue
            }
            
            for relayer in event.remaining {
                if relayer.last_attempt == nil ||
                   (now >= (relayer.last_attempt! + Int64(relayer.retry_after))) {
                    print("attempt #\(relayer.attempts) to flush event '\(event.event.content)' to \(relayer.relay) after \(relayer.retry_after) seconds")
                    await flush_event(event, to_relay: relayer)
                }
            }
        }
    }

    func handle_event(relay_id: RelayURL, _ ev: NostrConnectionEvent) {
        guard case .nostr_event(let resp) = ev else {
            return
        }
        
        guard case .ok(let cr) = resp else {
            return
        }
        
        remove_relayer(relay_id: relay_id, event_id: cr.event_id)
    }

    @discardableResult
    func remove_relayer(relay_id: RelayURL, event_id: NoteId) -> Bool {
        guard let ev = self.events[event_id] else {
            return false
        }
        
        if let on_flush = ev.on_flush {
            switch on_flush {
            case .once(let cb):
                if !ev.flushed_once {
                    ev.flushed_once = true
                    cb(ev)
                }
            case .all(let cb):
                cb(ev)
            }
        }
        
        let prev_count = ev.remaining.count
        ev.remaining = ev.remaining.filter { $0.relay != relay_id }
        let after_count = ev.remaining.count
        if ev.remaining.count == 0 {
            self.events.removeValue(forKey: event_id)
        }
        return prev_count != after_count
    }
    
    private func flush_event(_ event: PostedEvent, to_relay: Relayer? = nil) async {
        var relayers = event.remaining
        if let to_relay {
            relayers = [to_relay]
        }

        for relayer in relayers {
            relayer.attempts += 1
            relayer.last_attempt = Int64(Date().timeIntervalSince1970)
            relayer.retry_after *= 1.5
            if await pool.get_relay(relayer.relay) != nil {
                print("flushing event \(event.event.id) to \(relayer.relay)")
            } else {
                print("could not find relay when flushing: \(relayer.relay)")
            }
            await pool.send(.event(event.event), to: [relayer.relay], skip_ephemeral: event.skip_ephemeral)
        }

        // On first flush: republish author's relay list and trigger inbox delivery
        if !event.inboxDeliveryEvaluated {
            event.inboxDeliveryEvaluated = true

            // NIP-65: send the author's kind:10002 to the same relays so recipients
            // can discover how to reach the author.
            if !event.is_targeted, let ndb = self.ndb {
                let relayURLs = relayers.map { $0.relay }
                if let authorRelayList = InboxRelayResolver.lookupRelayListEvent(ndb: ndb, pubkey: event.event.pubkey) {
                    await pool.send(.event(authorRelayList), to: relayURLs, skip_ephemeral: event.skip_ephemeral)
                }
            }

            dispatchInboxDelivery(for: event)
        }
    }

    func send(_ event: NostrEvent, to: [RelayURL]? = nil, skip_ephemeral: Bool = true, delay: TimeInterval? = nil, on_flush: OnFlush? = nil) async {
        // Don't add event if we already have it
        if events[event.id] != nil {
            return
        }

        let remaining: [RelayURL]
        if let to {
            remaining = to
        }
        else {
            remaining = await pool.our_descriptors.map { $0.url }
        }
        let after = delay.map { d in Date.now.addingTimeInterval(d) }
        let posted_ev = PostedEvent(event: event, remaining: remaining, skip_ephemeral: skip_ephemeral, flush_after: after, on_flush: on_flush, is_targeted: to != nil)

        events[event.id] = posted_ev

        if after == nil {
            await flush_event(posted_ev)
        }
    }

    // MARK: - NIP-65 Inbox Delivery

    /// Dispatches inbox delivery as a fire-and-forget background task.
    /// Only dispatches when the event is a normal broadcast (not targeted) with p-tags and ndb is available.
    private func dispatchInboxDelivery(for posted: PostedEvent) {
        // Skip targeted sends (e.g. NWC payments to a specific relay)
        guard !posted.is_targeted else { return }
        guard let ndb = self.ndb else { return }

        // Only for events with p-tags
        let event = posted.event
        var hasPTags = false
        for _ in event.referenced_pubkeys {
            hasPTags = true
            break
        }
        guard hasPTags else { return }

        let pool = self.pool

        Task.detached(priority: .utility) {
            await PostBox.deliverToInboxRelays(event: event, pool: pool, ndb: ndb)
        }
    }

    /// Fetches kind:10002 relay lists from the network for any tagged pubkeys missing them in NDB.
    ///
    /// Returns parsed relay lists keyed by pubkey for immediate use. Events are also
    /// ingested into NDB for future cache benefit, but the caller does not depend on
    /// NDB queryability (avoids both the pool-without-NDB case and the ingester queue race).
    ///
    /// Only queries the user's own relays (non-ephemeral) to avoid leaking the pubkey
    /// set to NWC wallet relays or other ephemeral connections.
    private static func fetchMissingRelayLists(event: NostrEvent, pool: RelayPool, ndb: Ndb) async -> [Pubkey: NIP65.RelayList] {
        // Dedupe and cap the pubkey list to avoid oversized REQs on hellthreads.
        // MAX_INBOX_RELAYS bounds the final relay set, so fetching more lists is wasteful
        // and leaks the full mention set to the network.
        let allMissing = InboxRelayResolver.pubkeysMissingRelayLists(event: event, ndb: ndb)
        guard !allMissing.isEmpty else { return [:] }
        let missingPubkeys = Array(Set(allMissing).prefix(InboxRelayResolver.MAX_INBOX_RELAYS))

        #if DEBUG
        print("[PostBox] Fetching \(missingPubkeys.count) missing relay lists from network (capped from \(allMissing.count))")
        #endif

        // Scope to non-ephemeral relays only (excludes NWC wallet relays)
        let targetRelays = await pool.our_descriptors.map { $0.url }
        guard !targetRelays.isEmpty else { return [:] }

        let filter = NostrFilter(kinds: [.relay_list], authors: missingPubkeys)
        let stream = await pool.subscribeExistingItems(filters: [filter], to: targetRelays, eoseTimeout: .seconds(3))

        // Parse relay lists directly from the stream for immediate use.
        // Also ingest into NDB so future lookups find them without a network fetch.
        var fetched: [Pubkey: NIP65.RelayList] = [:]
        for await receivedEvent in stream {
            if let relayList = try? NIP65.RelayList(event: receivedEvent) {
                fetched[receivedEvent.pubkey] = relayList
            }
            // Best-effort cache into NDB (may already be ingested by pool.ndb)
            if let json = encode_json(receivedEvent) {
                ndb.processEvent("[\"EVENT\",\"fetch\",\(json)]")
            }
        }
        return fetched
    }

    /// Resolves inbox relays for tagged pubkeys and delivers the event to them.
    ///
    /// This is fire-and-forget: failures are logged but never block the normal publish path.
    static func deliverToInboxRelays(event: NostrEvent, pool: RelayPool, ndb: Ndb) async {
        // Fetch any missing relay lists from the network before resolving.
        // Returns parsed relay lists directly — no dependency on NDB queryability.
        let fetchedRelayLists = await fetchMissingRelayLists(event: event, pool: pool, ndb: ndb)

        // Only exclude relays the event was actually written to (writable relays).
        // our_descriptors includes read-only relays too, but RelayPool.send skips
        // writes to those, so they should not be subtracted from inbox fanout.
        let authorRelays = await Set(pool.our_descriptors.filter { $0.info.canWrite }.map { $0.url })
        let inboxRelays = InboxRelayResolver.resolveInboxRelays(event: event, ndb: ndb, excludeRelays: authorRelays, additionalRelayLists: fetchedRelayLists)

        guard !inboxRelays.isEmpty else { return }

        #if DEBUG
        print("[PostBox] Inbox delivery: sending to \(inboxRelays.map { $0.absoluteString })")
        #endif

        // Acquire ephemeral leases so the relays aren't cleaned up while we send
        await pool.acquireEphemeralRelays(inboxRelays)

        // Connect (adds as ephemeral if not already present) and wait up to 2s
        let connected = await pool.ensureConnected(to: inboxRelays)

        guard !connected.isEmpty else {
            #if DEBUG
            print("[PostBox] Inbox delivery: no relays connected, skipping")
            #endif
            await pool.releaseEphemeralRelays(inboxRelays)
            return
        }

        // Send the event to connected inbox relays
        await pool.send(.event(event), to: connected, skip_ephemeral: false)

        // Also send the author's kind:10002 relay list if available (NIP-65 republish requirement)
        if let authorRelayListEvent = InboxRelayResolver.lookupRelayListEvent(ndb: ndb, pubkey: event.pubkey) {
            await pool.send(.event(authorRelayListEvent), to: connected, skip_ephemeral: false)
        }

        #if DEBUG
        print("[PostBox] Inbox delivery: sent to \(connected.count) relays, waiting grace period")
        #endif

        // Grace period before releasing ephemeral leases
        try? await Task.sleep(for: .seconds(5))
        await pool.releaseEphemeralRelays(inboxRelays)

        #if DEBUG
        print("[PostBox] Inbox delivery: released ephemeral leases")
        #endif
    }
}


