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
    var acknowledged: Bool = false
    let enqueuedAt: Date

    init(event: NostrEvent, remaining: [RelayURL], skip_ephemeral: Bool, flush_after: Date?, on_flush: OnFlush?) {
        self.event = event
        self.skip_ephemeral = skip_ephemeral
        self.flush_after = flush_after
        self.on_flush = on_flush
        self.flushed_once = false
        self.remaining = remaining.map {
            Relayer(relay: $0, attempts: 0, retry_after: 10.0)
        }
        self.enqueuedAt = Date.now
    }
}

enum CancelSendErr {
    case nothing_to_cancel
    case not_delayed
    case too_late
}

class PostBox {
    private let pool: RelayPool
    private let pendingStore: PendingPostStore?
    var events: [NoteId: PostedEvent]
    
    private enum Constants {
        static let maxRelayAttempts = 8
        static let maxRetryInterval: Double = 60
        static let pendingEventTimeout: TimeInterval = 60 * 5
        static let connectivityPollInterval: UInt64 = 200_000_000 // 0.2s
        static let connectivityWait: TimeInterval = 5
    }

    init(pool: RelayPool, pendingStore: PendingPostStore? = nil) {
        self.pool = pool
        self.pendingStore = pendingStore
        self.events = [:]
        Task {
            let stream = AsyncStream<(RelayURL, NostrConnectionEvent)> { streamContinuation in
                Task { await self.pool.register_handler(sub_id: "postbox", filters: nil, to: nil, handler: streamContinuation) }
            }
            for await (relayUrl, connectionEvent) in stream {
                handle_event(relay_id: relayUrl, connectionEvent)
            }
        }
        Task {
            await waitForInitialConnectivity()
            await restorePendingPosts()
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
        removeExpiredEvents()
        var eventsToDrop: [NoteId] = []
        for (noteId, event) in events {
            // some are delayed
            if let after = event.flush_after, Date.now.timeIntervalSince1970 < after.timeIntervalSince1970 {
                continue
            }
            
            event.remaining.removeAll { relayer in
                relayer.attempts >= Constants.maxRelayAttempts
            }
            
            if event.remaining.isEmpty {
                eventsToDrop.append(noteId)
                continue
            }
            
            for relayer in event.remaining {
                let lastAttempt = relayer.last_attempt ?? 0
                let nextWindow = lastAttempt + Int64(relayer.retry_after)
                if relayer.last_attempt != nil && now < nextWindow {
                    continue
                }
                
                print("attempt #\(relayer.attempts) to flush event '\(event.event.content)' to \(relayer.relay) after \(relayer.retry_after) seconds")
                await flush_event(event, to_relay: relayer)
            }
        }
        
        if eventsToDrop.isEmpty {
            return
        }
        for noteId in eventsToDrop {
            print("dropping pending note \(noteId.hex()) after exhausting relay attempts")
            dropPending(noteId: noteId)
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
        if !ev.acknowledged && prev_count != after_count {
            ev.acknowledged = true
            if let pendingStore {
                Task { await pendingStore.markSent(event_id) }
            }
        }

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
            relayer.retry_after = min(relayer.retry_after * 1.5, Constants.maxRetryInterval)
            if await pool.get_relay(relayer.relay) != nil {
                print("flushing event \(event.event.id) to \(relayer.relay)")
            } else {
                print("could not find relay when flushing: \(relayer.relay)")
            }
            await pool.send(.event(event.event), to: [relayer.relay], skip_ephemeral: event.skip_ephemeral)
        }
    }

    func send(_ event: NostrEvent, to: [RelayURL]? = nil, skip_ephemeral: Bool = true, delay: TimeInterval? = nil, on_flush: OnFlush? = nil, trackPending: Bool = true) async {
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
        let posted_ev = PostedEvent(event: event, remaining: remaining, skip_ephemeral: skip_ephemeral, flush_after: after, on_flush: on_flush)

        events[event.id] = posted_ev
        if trackPending, let pendingStore {
            await pendingStore.track(event: event)
        }
        
        if after == nil {
            await flush_event(posted_ev)
        }
    }

    func dropPending(noteId: NoteId) {
        events.removeValue(forKey: noteId)
        if let pendingStore {
            Task { await pendingStore.remove(noteId) }
        }
    }
    
    private func restorePendingPosts() async {
        guard let pendingStore else { return }
        let events = await pendingStore.pendingEvents()
        for event in events {
            await send(event, skip_ephemeral: true, trackPending: false)
        }
    }
    
    private func waitForInitialConnectivity() async {
        let deadline = Date.now.addingTimeInterval(Constants.connectivityWait)
        while Date.now < deadline {
            if await hasConnectedRelay() {
                return
            }
            try? await Task.sleep(nanoseconds: Constants.connectivityPollInterval)
        }
    }
    
    private func hasConnectedRelay() async -> Bool {
        await pool.num_connected > 0
    }
    
    private func removeExpiredEvents() {
        let referenceDate = Date.now
        var expired: [NoteId] = []
        for (noteId, event) in events {
            if referenceDate.timeIntervalSince(event.enqueuedAt) > Constants.pendingEventTimeout {
                expired.append(noteId)
            }
        }
        if expired.isEmpty {
            return
        }
        for noteId in expired {
            print("dropping pending note \(noteId.hex()) after timeout while offline")
            dropPending(noteId: noteId)
        }
    }
}
