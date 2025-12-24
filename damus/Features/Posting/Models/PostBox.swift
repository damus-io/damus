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

    init(event: NostrEvent, remaining: [RelayURL], skip_ephemeral: Bool, flush_after: Date?, on_flush: OnFlush?) {
        self.event = event
        self.skip_ephemeral = skip_ephemeral
        self.flush_after = flush_after
        self.on_flush = on_flush
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

/// Work item for flushing events - contains immutable snapshot of data needed for network send
private struct FlushWorkItem {
    let eventId: NoteId
    let event: NostrEvent
    let relayURL: RelayURL
    let skipEphemeral: Bool
}

/// Manages pending events to be sent to relays, with retry logic and delayed send support.
///
/// Thread-safety model:
/// - All access to `_events` is protected by `lock`
/// - Mutable state (Relayer properties, PostedEvent.flushed_once) is only mutated under lock
/// - Network sends happen outside the lock to avoid blocking other operations
/// - Callbacks are captured under lock but executed outside to prevent deadlocks
class PostBox {
    private let pool: RelayPool

    /// Protects `_events` dictionary. All reads/writes must go through lock.
    private let lock = NSLock()
    private var _events: [NoteId: PostedEvent] = [:]

    /// Thread-safe read-only access to events (for testing/inspection)
    var events: [NoteId: PostedEvent] {
        lock.withLock { _events }
    }

    /// Atomically inserts an event only if the ID is not already present.
    /// Returns true if inserted, false if already present.
    private func setEventIfAbsent(_ id: NoteId, _ event: PostedEvent) -> Bool {
        lock.withLock {
            guard _events[id] == nil else { return false }
            _events[id] = event
            return true
        }
    }

    // MARK: - Initialization

    init(pool: RelayPool) {
        self.pool = pool
        Task {
            let stream = AsyncStream<(RelayURL, NostrConnectionEvent)> { streamContinuation in
                Task { await self.pool.register_handler(sub_id: "postbox", filters: nil, to: nil, handler: streamContinuation) }
            }
            for await (relayUrl, connectionEvent) in stream {
                handle_event(relay_id: relayUrl, connectionEvent)
            }
        }
    }

    // MARK: - Public methods

    /// Cancel a delayed event send. Only works reliably on delay-sent events.
    func cancel_send(evid: NoteId) -> CancelSendErr? {
        return lock.withLock {
            guard let ev = _events[evid] else {
                return .nothing_to_cancel
            }

            guard let after = ev.flush_after else {
                return .not_delayed
            }

            guard Date.now < after else {
                return .too_late
            }

            _ = _events.removeValue(forKey: evid)
            return nil
        }
    }

    func try_flushing_events() async {
        let now = Int64(Date().timeIntervalSince1970)

        // Build work list under lock - snapshot all data needed for sends
        let workItems: [FlushWorkItem] = lock.withLock {
            var items: [FlushWorkItem] = []
            for (eventId, event) in _events {
                // Skip delayed events
                if let after = event.flush_after, Date.now.timeIntervalSince1970 < after.timeIntervalSince1970 {
                    continue
                }

                for relayer in event.remaining {
                    // Skip if not ready for retry yet
                    let readyForRetry = relayer.last_attempt == nil ||
                                        now >= (relayer.last_attempt! + Int64(relayer.retry_after))
                    guard readyForRetry else { continue }

                    print("attempt #\(relayer.attempts) to flush event '\(event.event.content)' to \(relayer.relay) after \(relayer.retry_after) seconds")
                    relayer.attempts += 1
                    relayer.last_attempt = Int64(Date().timeIntervalSince1970)
                    relayer.retry_after *= 1.5
                    items.append(FlushWorkItem(
                        eventId: eventId,
                        event: event.event,
                        relayURL: relayer.relay,
                        skipEphemeral: event.skip_ephemeral
                    ))
                }
            }
            return items
        }

        // Perform network sends outside lock
        for item in workItems {
            if await pool.get_relay(item.relayURL) != nil {
                print("flushing event \(item.eventId) to \(item.relayURL)")
            } else {
                print("could not find relay when flushing: \(item.relayURL)")
            }
            await pool.send(.event(item.event), to: [item.relayURL], skip_ephemeral: item.skipEphemeral)
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
        // Perform all state mutations under lock, capture callback info for execution outside lock
        let callbackInfo: (callback: ((PostedEvent) -> Void)?, event: PostedEvent, removed: Bool)? = lock.withLock {
            guard let ev = _events[event_id] else {
                return nil
            }

            let prev_count = ev.remaining.count
            ev.remaining = ev.remaining.filter { $0.relay != relay_id }
            let removed = prev_count != ev.remaining.count

            // Determine which callback to invoke (if any)
            var callbackToInvoke: ((PostedEvent) -> Void)? = nil
            if let on_flush = ev.on_flush {
                switch on_flush {
                case .once(let cb):
                    if !ev.flushed_once {
                        ev.flushed_once = true
                        callbackToInvoke = cb
                    }
                case .all(let cb):
                    callbackToInvoke = cb
                }
            }

            // Remove event if no relayers remaining
            if ev.remaining.isEmpty {
                _ = _events.removeValue(forKey: event_id)
            }

            return (callbackToInvoke, ev, removed)
        }

        guard let info = callbackInfo else {
            return false
        }

        // Execute callback outside lock to avoid potential deadlocks
        info.callback?(info.event)

        return info.removed
    }

    // MARK: - Private methods

    /// Flush event to relays. Called only for immediate sends (no delay).
    /// Relayer state mutations are done under lock, network sends outside lock.
    private func flush_event(_ event: PostedEvent, to_relay: Relayer? = nil) async {
        // Build work items under lock - snapshot data needed for network sends
        let workItems: [FlushWorkItem] = lock.withLock {
            let relayers = to_relay.map { [$0] } ?? event.remaining

            var items: [FlushWorkItem] = []
            for relayer in relayers {
                relayer.attempts += 1
                relayer.last_attempt = Int64(Date().timeIntervalSince1970)
                relayer.retry_after *= 1.5
                items.append(FlushWorkItem(
                    eventId: event.event.id,
                    event: event.event,
                    relayURL: relayer.relay,
                    skipEphemeral: event.skip_ephemeral
                ))
            }
            return items
        }

        // Perform network sends outside lock
        for item in workItems {
            if await pool.get_relay(item.relayURL) != nil {
                print("flushing event \(item.eventId) to \(item.relayURL)")
            } else {
                print("could not find relay when flushing: \(item.relayURL)")
            }
            await pool.send(.event(item.event), to: [item.relayURL], skip_ephemeral: item.skipEphemeral)
        }
    }

    func send(_ event: NostrEvent, to: [RelayURL]? = nil, skip_ephemeral: Bool = true, delay: TimeInterval? = nil, on_flush: OnFlush? = nil) async {
        let remaining = to ?? await pool.our_descriptors.map { $0.url }
        let flush_after = delay.map { Date.now.addingTimeInterval($0) }
        let posted_ev = PostedEvent(event: event, remaining: remaining, skip_ephemeral: skip_ephemeral, flush_after: flush_after, on_flush: on_flush)

        // Atomic insert prevents duplicate sends for the same event
        guard setEventIfAbsent(event.id, posted_ev) else { return }

        // Flush immediately if no delay specified
        guard flush_after == nil else { return }
        await flush_event(posted_ev)
    }
}

