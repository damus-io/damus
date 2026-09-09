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

/// Delivery evidence for durable voice drafts. A transport attempt is never an acceptance.
enum PostBoxDelivery {
    case queued
    case dispatched(RelayURL)
    case accepted(RelayURL)
    case rejected(RelayURL, String)
    case noRelays
}

private final class VoicePostDelivery {
    let isActive: @Sendable () -> Bool
    let update: @Sendable (PostBoxDelivery) async -> Void
    init(isActive: @escaping @Sendable () -> Bool, update: @escaping @Sendable (PostBoxDelivery) async -> Void) {
        self.isActive = isActive
        self.update = update
    }
}

actor PostBox {
    private let pool: RelayPool
    var events: [NoteId: PostedEvent]
    private var voiceDeliveries: [NoteId: VoicePostDelivery] = [:]

    init(pool: RelayPool) {
        self.pool = pool
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
        for event in Array(events.values) {
            if let delivery = voiceDeliveries[event.event.id] {
                guard delivery.isActive() else {
                    voiceDeliveries.removeValue(forKey: event.event.id)
                    events.removeValue(forKey: event.event.id)
                    continue
                }
                if event.remaining.isEmpty {
                    event.remaining = await pool.our_descriptors.filter { $0.info.canWrite }.map {
                        Relayer(relay: $0.url, attempts: 0, retry_after: 10)
                    }
                    if event.remaining.isEmpty { continue }
                }
            }
            
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

    func handle_event(relay_id: RelayURL, _ ev: NostrConnectionEvent) async {
        guard case .nostr_event(.ok(let result)) = ev else { return }
        if let delivery = voiceDeliveries[result.event_id] {
            guard events[result.event_id]?.remaining.contains(where: { $0.relay == relay_id }) == true else { return }
            if result.ok {
                await delivery.update(.accepted(relay_id))
            } else {
                await delivery.update(.rejected(relay_id, result.msg))
                // Keep the same signed event available for retry; rejection is not on_flush success.
                return
            }
        }
        // Voice reposts use the normal queue, but a negative OK is still a rejection.
        if !result.ok, events[result.event_id]?.event.known_kind == .voice_repost { return }
        remove_relayer(relay_id: relay_id, event_id: result.event_id)
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
            self.voiceDeliveries.removeValue(forKey: event_id)
        }
        return prev_count != after_count
    }
    
    private func flush_event(_ event: PostedEvent, to_relay: Relayer? = nil) async {
        let voiceDelivery = voiceDeliveries[event.event.id]
        var relayers = event.remaining
        if let to_relay {
            relayers = [to_relay]
        }
        
        for relayer in relayers {
            guard events[event.event.id] === event else { return }
            if let voiceDelivery, !voiceDelivery.isActive() { return }
            relayer.attempts += 1
            relayer.last_attempt = Int64(Date().timeIntervalSince1970)
            relayer.retry_after *= 1.5
            if await pool.get_relay(relayer.relay) != nil {
                print("flushing event \(event.event.id) to \(relayer.relay)")
            } else {
                print("could not find relay when flushing: \(relayer.relay)")
            }
            if let voiceDelivery, !voiceDelivery.isActive() { return }
            await pool.send(.event(event.event), to: [relayer.relay], skip_ephemeral: event.skip_ephemeral)
            if let voiceDelivery { await voiceDelivery.update(.dispatched(relayer.relay)) }
        }
    }

    /// The caller must persist the exact signed voice event before requesting this handoff.
    func sendVoice(_ event: NostrEvent, isActive: @escaping @Sendable () -> Bool,
                   update: @escaping @Sendable (PostBoxDelivery) async -> Void) async {
        guard event.known_kind == .voice, !event.is_rumor, isActive() else { return }
        voiceDeliveries[event.id] = VoicePostDelivery(isActive: isActive, update: update)
        await update(.queued)
        let relays = await pool.our_descriptors.filter { $0.info.canWrite }.map { $0.url }
        guard isActive() else { voiceDeliveries.removeValue(forKey: event.id); return }
        if let pending = events[event.id] {
            if pending.remaining.isEmpty { pending.remaining = relays.map { Relayer(relay: $0, attempts: 0, retry_after: 10) } }
            await flush_event(pending)
        } else {
            await send(event, to: relays)
        }
        if relays.isEmpty { await update(.noRelays) }
    }

    func send(_ event: NostrEvent, to: [RelayURL]? = nil, skip_ephemeral: Bool = true, delay: TimeInterval? = nil, on_flush: OnFlush? = nil) async {
        // Never queue a rumor. A rumor is an unsigned note nostrdb unwrapped out of a NIP-59
        // giftwrap (see `NdbNote.is_rumor`), so its JSON carries a bogus signature and its
        // content is the plaintext of a private message. `make_nostr_push_event` refuses to
        // encode one too, but a rejection there would leave the event queued and retrying
        // forever — so keep it out of the queue in the first place.
        if event.is_rumor {
            Log.error("PostBox: refusing to queue rumor %s", for: .networking, event.id.hex())
            return
        }

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
        
        if after == nil {
            await flush_event(posted_ev)
        }
    }
}


