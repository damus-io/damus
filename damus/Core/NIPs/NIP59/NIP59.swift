//
//  NIP59.swift
//  damus
//
//  Created by Claude on 2026-09-03.
//
import Foundation

/// Functions and utilities for the NIP-59 gift wrap spec.
///
/// A gift wrap hides everything about a message except that *somebody* sent *something* to the
/// pubkey the wrap is addressed to. It gets there by nesting three layers:
///
/// 1. a **rumor** — the real event, left unsigned, so holding one proves nothing about who wrote it;
/// 2. a **seal** (kind 13) — the rumor's JSON, NIP-44 encrypted to the receiver and signed by the
///    real sender, which is the only thing that establishes authorship;
/// 3. a **gift wrap** (kind 1059) — the seal's JSON, NIP-44 encrypted to the receiver from a
///    throwaway key that also signs the wrap, so the sender's pubkey appears nowhere in public.
///
/// Only the gift wrap is ever published. This file is the write side only: we never *read* one of
/// these in Swift, because nostrdb's ingester peels inbound wraps and stores the rumor inside as an
/// ordinary note (see ``NdbNote/is_rumor``).
struct NIP59 {}

extension NIP59 {
    /// An unsigned nostr event — NIP-59's "rumor", the innermost layer of a gift wrap.
    ///
    /// Deliberately **not** a ``NostrEvent``. A rumor is the plaintext of a private message and must
    /// never reach a relay, and keeping it out of the type the egress path speaks makes that a
    /// property of the type system rather than something a guard has to catch at runtime. The runtime
    /// guards in `PostBox.send` and `make_nostr_push_event` test ``NdbNote/is_rumor``, which is
    /// nostrdb's `NDB_NOTE_FLAG_RUMOR` — a flag only nostrdb's unwrapper sets. A rumor built here has
    /// never been near nostrdb, so it would sail straight past both of them; not being a
    /// ``NostrEvent`` at all is what actually keeps it off the wire.
    struct Rumor {
        /// The usual NIP-01 event id. A rumor has one even though it is unsigned: the receiver's
        /// client needs something to address the message by, and it is what nostrdb recomputes when
        /// it stores the rumor it peeled out of a wrap.
        let id: NoteId
        /// The real sender. Public here only because the rumor never leaves its seal.
        let pubkey: Pubkey
        /// The real send time, unlike the seal's and the wrap's, which are deliberately noise.
        let created_at: UInt32
        let kind: UInt32
        let tags: [[String]]
        let content: String

        init(pubkey: Pubkey, kind: UInt32, tags: [[String]], content: String, createdAt: UInt32) {
            self.pubkey = pubkey
            self.kind = kind
            self.tags = tags
            self.content = content
            self.created_at = createdAt
            self.id = calculate_event_id(pubkey: pubkey, created_at: createdAt, kind: kind, tags: tags, content: content)
        }

        /// The rumor as JSON: an ordinary event object with the `sig` field left out.
        ///
        /// That missing signature is the whole point of a rumor, and it is why this cannot go through
        /// ``NostrEvent``'s encoder, which always emits a `sig`.
        var json: String? {
            encode_json(Wire(id: self.id, pubkey: self.pubkey, created_at: self.created_at,
                             kind: self.kind, tags: self.tags, content: self.content))
        }

        /// The JSON shape of a rumor. Field order does not matter to a parser; the absence of `sig`
        /// does.
        private struct Wire: Encodable {
            let id: NoteId
            let pubkey: Pubkey
            let created_at: UInt32
            let kind: UInt32
            let tags: [[String]]
            let content: String
        }
    }
}

extension NIP59 {
    /// Seals `rumor` for `receiver`: a kind-13 event whose content is the rumor's JSON, NIP-44
    /// encrypted from `sender` to `receiver` and signed by `sender`.
    ///
    /// The seal is the only layer that proves who sent the message, which is why the sender signs it
    /// and why it carries no tags — a tag here would leak, in the clear, something the wrap around it
    /// exists to hide.
    ///
    /// - Parameter createdAt: pass a timestamp from ``fuzzedTimestamp(now:)``. NIP-59 wants this
    ///   randomized; the caller supplies it so that a test can pin it.
    static func seal(rumor: Rumor, sender: FullKeypair, receiver: Pubkey, createdAt: UInt32) throws -> NostrEvent {
        guard let rumorJson = rumor.json else { throw GiftWrapError.rumorSerializationFailed }

        let sealedRumor = try NIP44v2Encryption.encrypt(plaintext: rumorJson,
                                                        privateKeyA: sender.privkey,
                                                        publicKeyB: receiver)

        guard let seal = NostrEvent(content: sealedRumor,
                                    keypair: sender.to_keypair(),
                                    kind: NostrKind.seal.rawValue,
                                    tags: [],
                                    createdAt: createdAt)
        else { throw GiftWrapError.sealConstructionFailed }

        return seal
    }

    /// Wraps `seal` for `receiver`: a kind-1059 event whose content is the seal's JSON, NIP-44
    /// encrypted to `receiver` from a **fresh** throwaway key that also signs the wrap.
    ///
    /// The ephemeral key is generated here, per call, and thrown away on return — never reused
    /// between wraps, not even for the two wraps of a single message. Reuse would republish the
    /// linkage the wrap exists to destroy: two wraps signed by the same one-off pubkey are provably
    /// from the same sender, which is exactly what an observer of the relay wants to learn.
    ///
    /// - Parameter createdAt: pass a timestamp from ``fuzzedTimestamp(now:)``, as for ``seal``.
    static func giftWrap(seal: NostrEvent, receiver: Pubkey, createdAt: UInt32) throws -> NostrEvent {
        guard let sealJson = encode_json(seal) else { throw GiftWrapError.sealSerializationFailed }

        let ephemeral = generate_new_keypair()
        let wrappedSeal = try NIP44v2Encryption.encrypt(plaintext: sealJson,
                                                        privateKeyA: ephemeral.privkey,
                                                        publicKeyB: receiver)

        guard let wrap = NostrEvent(content: wrappedSeal,
                                    keypair: ephemeral.to_keypair(),
                                    kind: NostrKind.giftwrap.rawValue,
                                    tags: [["p", receiver.hex()]],
                                    createdAt: createdAt)
        else { throw GiftWrapError.giftWrapConstructionFailed }

        return wrap
    }

    /// Gift wraps `rumor` for `receiver` in one step: rumor -> seal -> wrap.
    ///
    /// Both outer layers get their own independently randomized `created_at`, so the seal a receiver
    /// eventually decrypts does not carry the wrap's timestamp back out and undo the fuzzing.
    static func giftWrap(rumor: Rumor, sender: FullKeypair, receiver: Pubkey, now: UInt32 = UInt32(Date().timeIntervalSince1970)) throws -> NostrEvent {
        let sealedRumor = try seal(rumor: rumor, sender: sender, receiver: receiver, createdAt: fuzzedTimestamp(now: now))
        return try giftWrap(seal: sealedRumor, receiver: receiver, createdAt: fuzzedTimestamp(now: now))
    }

    /// A `created_at` for a seal or a gift wrap: `now`, moved a random amount into the past.
    ///
    /// NIP-59 asks for this to thwart time-analysis attacks — without it a relay operator can
    /// correlate the wraps of a conversation by the times they were published, which defeats much of
    /// the point of hiding the sender. The window is
    /// ``NostrKind/giftwrapCreatedAtFuzzWindow``, the same two days our inbound giftwrap
    /// subscription has to widen its `since` bound by to avoid dropping other clients' fuzzed wraps.
    ///
    /// Only ever into the *past*: a future timestamp is rejected outright by relays that enforce a
    /// `created_at` upper bound, so fuzzing forwards would silently lose messages.
    static func fuzzedTimestamp(now: UInt32 = UInt32(Date().timeIntervalSince1970)) -> UInt32 {
        let offset = UInt32.random(in: 0...NostrKind.giftwrapCreatedAtFuzzWindow)
        // Guard the subtraction rather than trusting the clock: `now` is under a minute past the
        // epoch on a device whose clock has not been set yet, and an underflow here would trap.
        return now > offset ? now - offset : 0
    }

    enum GiftWrapError: Error {
        /// The rumor could not be turned into the JSON a seal encrypts.
        case rumorSerializationFailed
        /// The seal could not be turned into the JSON a gift wrap encrypts.
        case sealSerializationFailed
        /// The kind-13 seal could not be built or signed.
        case sealConstructionFailed
        /// The kind-1059 gift wrap could not be built or signed.
        case giftWrapConstructionFailed
    }
}

extension NIP59 {
    /// A message that never leaves its gift wrap, built and ready to publish.
    ///
    /// Kind-agnostic, exactly as ``giftWrap(rumor:sender:receiver:now:)`` is: a private reply is a
    /// kind-1 rumor in this shape, a private reaction a kind-7 one, and a NIP-17 DM would be a kind-14
    /// one. What the type carries is not the kind but the two rules that hold whatever the kind is —
    /// the rumor is never published, and only one of the wraps may be ingested locally.
    struct PrivateEvent {
        /// The message itself. Never published, and not a ``NostrEvent`` — see ``NIP59/Rumor``.
        let rumor: NIP59.Rumor

        /// The gift wraps to publish, which is the *only* part of this that goes on a relay.
        ///
        /// Normally two: one addressed to ``audience`` and one addressed to ourselves.
        /// The second is not a convenience — it is the only copy of our own message that exists
        /// anywhere we can read, since the first is encrypted to the recipient and we cannot open it.
        let giftWraps: [NostrEvent]

        /// The one person this was addressed to — see ``NIP59/privateAudience(for:as:)``.
        ///
        /// The send path needs it to look up *whose* DM inbox relays ``giftWrapToReceiver`` goes to,
        /// and it is not always the parent's author, so it is carried here rather than re-derived.
        let audience: Pubkey

        /// The wrap addressed to us, i.e. the one whose rumor our own key can recover.
        ///
        /// Always one of ``giftWraps``. Ingesting *this* wrap into the local database — and only this
        /// one — is how something we sent appears locally: nostrdb peels it and the app's existing
        /// plaintext queries deliver the rumor. The receiver's wrap must never be ingested, because we
        /// cannot decrypt it, so it would sit in the database forever as an un-openable kind 1059 that
        /// every giftwrap backfill retries at every launch.
        let giftWrapToSelf: NostrEvent

        /// The wrap addressed to ``audience``, or `nil` when that is us.
        ///
        /// The two wraps go to different places — theirs to their kind-10050 DM inbox relays, ours to
        /// our own — so the send path has to tell them apart. They are distinguishable only by
        /// identity, since every other field of a wrap is deliberately unlinkable noise.
        var giftWrapToReceiver: NostrEvent? {
            return giftWraps.first(where: { $0.id != giftWrapToSelf.id })
        }
    }

    /// The single person a private message *about* `parent` is addressed to.
    ///
    /// Almost always `parent`'s author. The exception is a private message of *our own*: its author is
    /// us, so the author rule would address the answer to ourselves and quietly end a conversation the
    /// user believes they are continuing. The person on the other end of that conversation is the one
    /// the parent was addressed to, which is its single `p` tag — on a rumor the `p` tags are not a
    /// mention list, they are the audience.
    ///
    /// So the rule is not "the parent's author" but "the parent's *counterparty*", which is the same
    /// thing in every case but this one. It keeps a private exchange 1:1 for its whole length and never
    /// adds a participant.
    ///
    /// The guard is ``NdbNote/is_rumor`` and not any kind, because what matters is that `parent` came
    /// out of a gift wrap — as true of a NIP-17 DM (kind 14) or a private reaction (kind 7) as of a
    /// private reply (kind 1). Reading the audience off a `p` tag is only safe because a rumor whose
    /// `pubkey` is ours can only have been built by us: nostrdb copies that pubkey off the *seal*, and
    /// a seal is signed, so nobody but the holder of our key can produce one that names us.
    ///
    /// Only ever consults the direct parent. A public note that happens to sit under a private
    /// ancestor — which our own client cannot produce, but another client could, by publicly replying
    /// to a rumor id — is answered publicly and addressed to its own author, with no inheritance from
    /// the thread. That is right: the note being answered is already public, and privacy is a property
    /// of a message rather than of a thread.
    static func privateAudience(for parent: NostrEvent, as us: Pubkey) -> Pubkey {
        guard parent.is_rumor, parent.pubkey == us,
              let counterparty = parent.referenced_pubkeys.first else {
            return parent.pubkey
        }
        return counterparty
    }

    /// Seals and wraps `rumor` for `receiver` and for ourselves, which is the only publishable form of
    /// a private message.
    ///
    /// The one place the two-wrap rule lives, so that every kind of private message obeys it
    /// identically. Two independent wraps, each with its own seal and its own throwaway signing key:
    /// reusing either across the pair would tie the two together on the relay and reveal that whoever
    /// sent one sent the other, which is the exact correlation the wrap exists to prevent.
    static func privateEvent(rumor: Rumor, to receiver: Pubkey, from keypair: FullKeypair) throws -> PrivateEvent {
        let wrapToSelf = try giftWrap(rumor: rumor, sender: keypair, receiver: keypair.pubkey)

        // Addressing ourselves is the degenerate case: the copy for the recipient and the copy for
        // ourselves are the same copy, and publishing a second would put the same message on the relay
        // twice under two unlinkable ephemeral keys for no gain.
        guard receiver != keypair.pubkey else {
            return PrivateEvent(rumor: rumor, giftWraps: [wrapToSelf], audience: receiver, giftWrapToSelf: wrapToSelf)
        }

        let wrapToReceiver = try giftWrap(rumor: rumor, sender: keypair, receiver: receiver)

        return PrivateEvent(rumor: rumor,
                            giftWraps: [wrapToReceiver, wrapToSelf],
                            audience: receiver,
                            giftWrapToSelf: wrapToSelf)
    }
}
