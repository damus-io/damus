//
//  Ndb+.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-04-04.
//

/// ## Implementation notes
///
/// 1. This was created as a separate file because it contains dependencies to damus-specific structures such as `NostrFilter`, which is not yet available inside the NostrDB codebase.

import Foundation

extension Ndb {
    /// Subscribe to events matching the provided NostrFilters
    /// - Parameters:
    ///   - filters: Array of NostrFilter objects
    ///   - maxSimultaneousResults: Maximum number of initial results to return
    /// - Returns: AsyncStream of StreamItem events
    /// - Throws: NdbStreamError if subscription fails
    func subscribe(filters: [NostrFilter], maxSimultaneousResults: Int = 1000) throws -> AsyncStream<StreamItem> {
        let ndbFilters: [NdbFilter]
        do {
            ndbFilters = try filters.toNdbFilters()
        } catch {
            throw NdbStreamError.cannotConvertFilter(error)
        }
        return try self.subscribe(filters: ndbFilters, maxSimultaneousResults: maxSimultaneousResults)
    }
    
    /// Determines if a given note was seen on any of the listed relay URLs
    func was(noteKey: NoteKey, seenOnAnyOf relayUrls: [RelayURL]) throws -> Bool {
        return try self.was(noteKey: noteKey, seenOnAnyOf: relayUrls.map({ $0.absoluteString }))
    }
    
    func processEvent(_ str: String, originRelayURL: RelayURL? = nil) -> Bool {
        self.process_event(str, originRelayURL: originRelayURL?.absoluteString)
    }
    
    /// Adds a NostrEvent to the database by converting it to a push event and processing it.
    /// - Parameter event: The NostrEvent to add
    /// - Throws: NdbAddError.couldNotMakePushEvent if the event cannot be converted, or NdbAddError.processingFailed if processing fails
    func add(event: NostrEvent) throws {
        guard let nostrPushEvent = make_nostr_push_event(ev: event) else {
            throw NdbAddError.couldNotMakePushEvent
        }
        let success = self.process_client_event(nostrPushEvent)
        if !success {
            throw NdbAddError.processingFailed
        }
    }
    
    enum NdbAddError: Error {
        case couldNotMakePushEvent
        case processingFailed
    }
}

// MARK: - Giftwrap unwrapping

extension Ndb {
    /// How many kind-14 rumors already in the database ``unwrapGiftwrap(_:timeout:)`` looks through
    /// before it stops expecting to find the one it is waiting for.
    ///
    /// Its subscription replays the rumors already stored before it starts delivering new ones, and
    /// that replay is the only path that can find a wrap somebody else already peeled. A cap keeps
    /// the replay from becoming a walk of every DM the user has ever received, inside a process the
    /// system gives a few seconds to live. nostrdb replays the newest first and a wrap we were just
    /// handed is about as new as a message gets, so a small window is enough.
    private static let giftwrapRumorReplayLimit: Int = 64

    /// Hands a kind-1059 giftwrap to nostrdb and waits for the kind-14 rumor it peels out of it.
    ///
    /// This is the only place in damus that *reads* a giftwrap, and even here nothing is decrypted in
    /// Swift: the unwrapping happens on nostrdb's ingester threads, using the key ``add_key(_:)``
    /// registered with them. All this does is push the wrap in one end and wait at the other.
    ///
    /// It exists for the notification extension, which the push server hands a single wrap and which
    /// has nothing it could possibly display until that wrap is open — a giftwrap is signed by a
    /// throwaway key, and the message, its sender and its real timestamp are all sealed inside. The
    /// app proper never needs this: wraps arriving from relays are peeled as they are ingested, and
    /// the DM list's `kinds: [14]` subscription picks the rumors up on its own.
    ///
    /// The subscription is opened *before* the wrap is ingested, which is what makes this work in
    /// both directions. A rumor that appears afterwards arrives live; one that was already stored —
    /// because this wrap had already been ingested, and nostrdb skips a note it already has rather
    /// than unwrapping it a second time — comes back in the replay instead.
    ///
    /// - Parameters:
    ///   - wrap: the kind-1059 giftwrap. Anything else is rejected rather than ingested.
    ///   - timeout: how long to wait for the rumor. Bounded because a wrap none of our keys can open
    ///     produces nothing and says nothing about it: `ndb_process_giftwrap` fails on an ingester
    ///     thread with no way to report back, so an unbounded caller would simply hang.
    /// - Returns: the plaintext kind-14 rumor, or `nil` if nothing came out of the wrap in time.
    func unwrapGiftwrap(_ wrap: NostrEvent, timeout: TimeInterval = 5) async -> NdbNote? {
        guard wrap.known_kind == .giftwrap else {
            Log.error("NIP-17: refusing to unwrap %s, which is a kind %d and not a giftwrap", for: .storage, wrap.id.hex(), Int(wrap.kind))
            return nil
        }

        let rumors: AsyncStream<StreamItem>
        do {
            rumors = try self.subscribe(filters: [NostrFilter(kinds: [.private_dm])],
                                        maxSimultaneousResults: Self.giftwrapRumorReplayLimit)
        }
        catch {
            Log.error("NIP-17: could not subscribe to rumors to unwrap giftwrap %s: %s", for: .storage, wrap.id.hex(), error.localizedDescription)
            return nil
        }

        do {
            try self.add(event: wrap)
        }
        catch {
            Log.error("NIP-17: could not hand giftwrap %s to the ingesters: %s", for: .storage, wrap.id.hex(), error.localizedDescription)
            return nil
        }

        return await withTaskGroup(of: NdbNote?.self, returning: NdbNote?.self) { group in
            group.addTask {
                for await item in rumors {
                    guard case .event(let noteKey) = item else { continue }   // skip eose
                    guard let rumor = try? self.lookup_note_by_key_and_copy(noteKey) else { continue }
                    // The subscription is on the whole kind rather than on this wrap, so every DM in
                    // the replay window turns up here too. `rumor_giftwrap_id` is what ties a rumor
                    // back to the wrap it came out of: nostrdb stashes it in the signature field,
                    // which an unsigned rumor has no other use for.
                    guard rumor.is_rumor, rumor.rumor_giftwrap_id == wrap.id else { continue }
                    return rumor
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                return nil
            }

            let firstResult = await group.next() ?? nil
            group.cancelAll()

            if firstResult == nil {
                // Every reason this can happen looks identical from here — no key registered, a wrap
                // addressed to someone else, a malformed seal, or just a slow ingester pool — so say
                // which wrap gave up rather than trying to guess why.
                Log.error("NIP-17: no rumor came out of giftwrap %s", for: .storage, wrap.id.hex())
            }
            return firstResult
        }
    }
}
