//
//  NIP17.swift
//  damus
//
//  Created by Claude on 2026-09-03.
//
import Foundation

/// Functions and utilities for the NIP-17 private direct message spec.
///
/// A NIP-17 message is a kind-14 rumor inside a NIP-59 gift wrap, so this is a thin layer over
/// ``NIP59``: it decides what goes in the rumor and who the wraps are addressed to, and NIP-59 does
/// the sealing and wrapping.
///
/// This is the send side. There is no receive side in Swift — nostrdb's ingester unwraps inbound
/// giftwraps and stores the kind-14 rumor inside as an ordinary plaintext note, which the DM models
/// read with a local `kinds: [14]` query.
struct NIP17 {}

extension NIP17 {
    /// A NIP-17 direct message, built and ready to publish.
    struct DirectMessage {
        /// The message itself. Never published, and not a ``NostrEvent`` — see ``NIP59/Rumor``.
        let rumor: NIP59.Rumor
        /// The gift wraps to publish, which is the *only* part of this that goes on a relay.
        ///
        /// Normally two: one addressed to the person we are talking to and one addressed to
        /// ourselves. The second is not a convenience — it is the only copy of our own sent message
        /// that exists anywhere we can read, since the first is encrypted to the recipient and we
        /// cannot open it. Without it our own side of every conversation would vanish the moment the
        /// local database was rebuilt.
        let giftWraps: [NostrEvent]
        /// The wrap addressed to us, i.e. the one whose rumor our own key can recover.
        ///
        /// Always one of ``giftWraps``. Ingesting *this* wrap into the local database — and only this
        /// one — is how a sent message appears in the conversation: nostrdb peels it and the kind-14
        /// subscription the DM list already reads delivers the rumor. The receiver's wrap must never
        /// be ingested, because we cannot decrypt it, so it would sit in the database forever as an
        /// un-openable kind 1059 that every giftwrap backfill retries at every launch.
        let giftWrapToSelf: NostrEvent

        /// The wrap addressed to the person we are talking to, or `nil` for a note to self.
        ///
        /// The two wraps go to different places — theirs to their kind-10050 DM inbox relays, ours to
        /// our own — so the send path has to tell them apart. They are distinguishable only by
        /// identity, since every other field of a wrap is deliberately unlinkable noise.
        var giftWrapToReceiver: NostrEvent? {
            return giftWraps.first(where: { $0.id != giftWrapToSelf.id })
        }
    }

    /// Builds a 1:1 NIP-17 direct message: a kind-14 rumor, sealed and wrapped once for `receiver`
    /// and once for ourselves.
    ///
    /// **1:1 only, deliberately.** The rumor carries a single `p` tag. NIP-17 allows several, but our
    /// read path drops any rumor with more than one counterparty (see `nip17_conversation_pubkey`):
    /// damus has no group chat UI, and folding a group into a 1:1 thread would show the user a thread
    /// they can only half see and let them reply into it reaching one participant. Sending to a group
    /// here would produce messages our own reader throws away.
    ///
    /// - Parameters:
    ///   - content: the message, in plaintext. It stays plaintext all the way into the rumor; the
    ///     seal is what encrypts it.
    ///   - receiver: the one other party to the conversation.
    ///   - keypair: our own keys. A full keypair, because the seal has to be signed by us — a
    ///     pubkey-only login cannot send a NIP-17 message.
    ///   - createdAt: the real send time, which is the rumor's `created_at` and the timestamp
    ///     conversations are ordered by. Unlike the seal's and the wraps', it is not fuzzed: it is
    ///     inside the encryption, so nobody but the two of us ever sees it.
    static func createDirectMessage(_ content: String,
                                    to receiver: Pubkey,
                                    keypair: FullKeypair,
                                    createdAt: UInt32 = UInt32(Date().timeIntervalSince1970)) throws -> DirectMessage {
        let rumor = NIP59.Rumor(pubkey: keypair.pubkey,
                                kind: NostrKind.private_dm.rawValue,
                                tags: [["p", receiver.hex()]],
                                content: content,
                                createdAt: createdAt)

        let wrapToSelf = try NIP59.giftWrap(rumor: rumor, sender: keypair, receiver: keypair.pubkey)

        // A note to self needs one wrap, not two: the copy for the receiver and the copy for
        // ourselves are the same copy, and publishing a second one would put the same message on the
        // relay twice under two unlinkable ephemeral keys for no gain.
        guard receiver != keypair.pubkey else {
            return DirectMessage(rumor: rumor, giftWraps: [wrapToSelf], giftWrapToSelf: wrapToSelf)
        }

        // Two independent wraps, each with its own seal and its own throwaway signing key. Reusing
        // either across the pair would tie the two wraps together on the relay and reveal that the
        // person who sent one sent the other — which is the correlation the wrap exists to prevent.
        let wrapToReceiver = try NIP59.giftWrap(rumor: rumor, sender: keypair, receiver: receiver)

        return DirectMessage(rumor: rumor,
                             giftWraps: [wrapToReceiver, wrapToSelf],
                             giftWrapToSelf: wrapToSelf)
    }
}

extension NIP17 {
    /// A NIP-17 DM inbox relay list: the kind-10050 event naming the relays a user reads private
    /// messages from.
    ///
    /// This is the NIP-17 counterpart to ``NIP65/RelayList``, and deliberately a separate type rather
    /// than a reuse of it. A NIP-65 entry carries a read/write marker and describes where a user's
    /// *public* notes flow; a kind-10050 entry is an unmarked `["relay", "<url>"]` and describes the
    /// one place a giftwrap addressed to that user has to land in order to be seen at all. Folding
    /// the two together would let a read/write marker silently exclude an inbox.
    struct DMRelayList: NostrEventConvertible, Sendable {
        typealias E = DMRelayListDecodingError

        /// The user's inbox relays, in the order the event lists them. Deduplicated, and possibly empty.
        let relays: [RelayURL]

        static let RELAY_TAG_KEY: String = "relay"

        // MARK: - Initialization

        init(event: NostrEvent) throws(DMRelayListDecodingError) {
            guard event.known_kind == .dm_relay_list else { throw .notDMRelayList }
            var relays: [RelayURL] = []
            var seen: Set<RelayURL> = []
            for tag in event.tags {
                var i = tag.makeIterator()
                guard tag.count >= 2,
                      let key = i.next(),
                      key.string() == Self.RELAY_TAG_KEY,
                      let value = i.next()
                else { continue }
                // A single unparseable URL is not a reason to throw away the rest of someone's inbox
                // list: dropping one relay costs us one delivery target, dropping the list costs us
                // every one of them and silently falls back to relays they may never read.
                guard let url = RelayURL(value.string()) else { continue }
                guard !seen.contains(url) else { continue }
                seen.insert(url)
                relays.append(url)
            }
            self.relays = relays
        }

        init(relays: [RelayURL]) {
            var seen: Set<RelayURL> = []
            self.relays = relays.filter({ seen.insert($0).inserted })
        }

        // MARK: - Conversion to a Nostr Event

        func toNostrEvent(keypair: FullKeypair, timestamp: UInt32? = nil) -> NostrEvent? {
            return NdbNote(
                content: "",
                keypair: keypair.to_keypair(),
                kind: NostrKind.dm_relay_list.rawValue,
                tags: self.relays.map({ [Self.RELAY_TAG_KEY, $0.absoluteString] }),
                createdAt: timestamp ?? UInt32(Date.now.timeIntervalSince1970)
            )
        }
    }

    /// An error thrown when decoding an event into a NIP-17 DM inbox relay list
    enum DMRelayListDecodingError: Error {
        /// The Nostr event being converted is not a kind-10050 DM relay list
        case notDMRelayList
    }
}
