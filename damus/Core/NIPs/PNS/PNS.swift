//
//  PNS.swift
//  damus
//
//  Created by Claude on 2026-09-03.
//
import Foundation
import CryptoKit

/// Private Notification Storage (NIP-1080) — a self-addressed envelope nostrdb opens for us at ingest.
///
/// A PNS envelope is a kind-1080 event whose content is a NIP-44 payload wrapping some other event.
/// It exists so a client can hand nostrdb something private and get an ordinary, queryable note back:
/// the ingester matches the envelope's author against the PNS keys registered by ``Ndb/add_key(_:)``,
/// decrypts it, and stores the event inside as a note flagged `NDB_NOTE_FLAG_RUMOR`
/// (see ``NdbNote/is_rumor``). Reading it afterwards is a plain query.
///
/// Two things make it much cheaper than a gift wrap, and they are why drafts are stored this way:
///
/// - **The key is symmetric and pre-derived.** Both the envelope's identity and its NIP-44
///   conversation key come out of the device secret by HKDF-Extract alone (see ``key(for:)``), so
///   opening one costs no `secp256k1_ecdh` — the ~5ms per draft that used to run on the main thread
///   at launch.
/// - **It is self-to-self by construction.** There is no recipient to address, no seal proving
///   authorship, and no reason to sign the event inside — which is exactly the shape of a draft.
///
/// This is the write side only. We never open one in Swift: nostrdb does that on its ingester
/// threadpool before the note is ever stored, which is the entire point.
struct PNS {
    /// The kind of a PNS envelope.
    ///
    /// Deliberately not a ``NostrKind`` case. Nothing in the app ever reads or routes one — the
    /// envelope's whole life is `sendToNostrDB` at one end and nostrdb's ingester at the other — so
    /// giving it a `known_kind` would only add a case to every exhaustive switch over kinds that
    /// could never fire.
    static let kind: UInt32 = 1080

    /// Salt for the device secret -> PNS secret step. Mirrors `nostrdb.c`'s `ndb_ingester_add_pns_key`.
    private static let keySalt = "nip-pns"
    /// Salt for the PNS secret -> NIP-44 conversation key step, the same salt NIP-44 uses for the
    /// conversation key it derives from an ECDH secret.
    private static let conversationKeySalt = "nip44-v2"

    /// The key material for one device's PNS envelopes.
    struct Key {
        /// The keypair an envelope is authored and signed by. Its pubkey is what nostrdb matches an
        /// inbound kind 1080 against, and it is *not* the user's pubkey — nothing about an envelope
        /// sitting on disk says whose it is.
        let keypair: FullKeypair
        /// The pre-derived NIP-44 conversation key the envelope's content is encrypted under.
        let conversationKey: ContiguousBytes
    }

    /// Derives the PNS key for a device secret, the same way nostrdb's ingester does.
    ///
    ///     pns_secret       = HKDF-Extract(salt: "nip-pns",  ikm: device_secret)
    ///     pns_nip44_key    = HKDF-Extract(salt: "nip44-v2", ikm: pns_secret)
    ///     pns_pubkey       = xonly_pubkey(pns_secret)
    ///
    /// This has to stay in lock step with `ndb_ingester_add_pns_key` in `nostrdb/src/nostrdb.c`: the
    /// ingester derives its half from the very same device secret and matches on the pubkey, so a
    /// divergence here does not fail loudly — it produces envelopes nostrdb quietly never opens.
    static func key(for deviceSecret: Privkey) throws -> Key {
        let secret = CryptoKit.HKDF<CryptoKit.SHA256>.extract(
            inputKeyMaterial: SymmetricKey(data: deviceSecret.id),
            salt: Data(keySalt.utf8)
        )
        guard let keypair = FullKeypair(privkey: Privkey(Data(secret))) else {
            throw PNSError.invalidDerivedKey
        }
        let conversationKey = CryptoKit.HKDF<CryptoKit.SHA256>.extract(
            inputKeyMaterial: SymmetricKey(data: Data(secret)),
            salt: Data(conversationKeySalt.utf8)
        )
        return Key(keypair: keypair, conversationKey: conversationKey)
    }

    /// Wraps `rumor` in a PNS envelope: a kind-1080 event whose content is the rumor's JSON, NIP-44
    /// encrypted under `key`'s conversation key and signed by `key`'s keypair.
    ///
    /// The envelope carries no tags. A tag here would be readable by anything that can see the
    /// database file, which is the one property the envelope exists to deny.
    static func envelope(rumor: NIP59.Rumor, key: Key, createdAt: UInt32 = UInt32(Date().timeIntervalSince1970)) throws -> NostrEvent {
        guard let rumorJson = rumor.json else { throw PNSError.rumorSerializationFailed }

        let content = try NIP44v2Encryption.encrypt(plaintext: rumorJson, conversationKey: key.conversationKey)

        guard let envelope = NostrEvent(content: content,
                                        keypair: key.keypair.to_keypair(),
                                        kind: Self.kind,
                                        tags: [],
                                        createdAt: createdAt)
        else { throw PNSError.envelopeConstructionFailed }

        return envelope
    }

    enum PNSError: Error {
        /// The device secret did not derive a usable PNS keypair.
        case invalidDerivedKey
        /// The event to be wrapped could not be turned into the JSON the envelope encrypts.
        case rumorSerializationFailed
        /// The kind-1080 envelope could not be built or signed.
        case envelopeConstructionFailed
    }
}
