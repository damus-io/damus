//
//  NIP17.swift
//  damus
//
//  NIP-17 Private Direct Messages implementation
//  Uses NIP-44 encryption and NIP-59 gift wrap structure
//
//  Reference: https://github.com/damus-io/notedeck/blob/master/crates/notedeck_messages/src/nip17/mod.rs
//

import Foundation

/// NIP-17 Private Direct Message utilities
///
/// Message structure: rumor (kind 14) → seal (kind 13) → gift_wrap (kind 1059)
/// - Rumor: Unsigned event containing the actual message
/// - Seal: Sender-signed event containing encrypted rumor
/// - Gift wrap: Ephemeral-key-signed event containing encrypted seal
struct NIP17 {

    // MARK: - Errors

    enum Error: Swift.Error {
        case encryptionFailed
        case decryptionFailed
        case invalidSeal
        case invalidRumor
        case invalidGiftWrap
        case missingPrivateKey
        case jsonEncodingFailed
        case jsonDecodingFailed
        case signatureFailed
    }

    // MARK: - Message Creation

    /// Creates a gift-wrapped NIP-17 direct message
    ///
    /// Creates two gift wraps: one for recipient (to receive) and one for sender (for cross-device recovery).
    /// Runs expensive keypair generation off the main thread.
    ///
    /// - Parameters:
    ///   - content: The message content
    ///   - recipient: The recipient's public key
    ///   - sender: The sender's full keypair
    ///   - replyTo: Optional note ID being replied to
    /// - Returns: Tuple of (recipientWrap, senderWrap) or nil on failure
    static func createMessage(
        content: String,
        to recipient: Pubkey,
        from sender: FullKeypair,
        replyTo: NoteId? = nil
    ) async -> (recipientWrap: NostrEvent, senderWrap: NostrEvent)? {

        // Build participant tags (recipient + sender for group context)
        var tags: [[String]] = [["p", recipient.hex()]]
        if let replyTo = replyTo {
            tags.append(["e", replyTo.hex(), "", "reply"])
        }

        // 1. Create rumor (unsigned kind 14)
        guard let rumorJson = buildRumorJson(
            content: content,
            senderPubkey: sender.pubkey,
            tags: tags
        ) else {
            return nil
        }

        // 2. Create seal for recipient
        guard let recipientWrap = await createGiftWrap(
            rumorJson: rumorJson,
            sender: sender,
            recipient: recipient
        ) else {
            return nil
        }

        // 3. Create seal for sender (self-wrap for recovery)
        guard let senderWrap = await createGiftWrap(
            rumorJson: rumorJson,
            sender: sender,
            recipient: sender.pubkey
        ) else {
            return nil
        }

        return (recipientWrap, senderWrap)
    }

    /// Creates a single gift wrap for a recipient.
    /// Generates ephemeral keypair on background thread to avoid blocking main thread.
    private static func createGiftWrap(
        rumorJson: String,
        sender: FullKeypair,
        recipient: Pubkey
    ) async -> NostrEvent? {

        // Encrypt rumor with NIP-44 (sender → recipient)
        guard let encryptedRumor = try? NIP44v2Encryption.encrypt(
            plaintext: rumorJson,
            privateKeyA: sender.privkey,
            publicKeyB: recipient
        ) else {
            return nil
        }

        // Create seal (kind 13)
        let sealCreatedAt = randomizedTimestamp()
        guard let sealJson = buildSealJson(
            encryptedContent: encryptedRumor,
            sender: sender,
            createdAt: sealCreatedAt
        ) else {
            return nil
        }

        // Generate ephemeral keypair on background thread (secp256k1 key generation is expensive)
        let wrapKeys = await Task.detached(priority: .userInitiated) {
            generate_new_keypair()
        }.value

        // Encrypt seal with NIP-44 (ephemeral → recipient)
        guard let encryptedSeal = try? NIP44v2Encryption.encrypt(
            plaintext: sealJson,
            privateKeyA: wrapKeys.privkey,
            publicKeyB: recipient
        ) else {
            return nil
        }

        // Create gift wrap (kind 1059)
        let wrapCreatedAt = randomizedTimestamp()
        return buildGiftWrap(
            encryptedContent: encryptedSeal,
            wrapKeys: wrapKeys,
            recipient: recipient,
            createdAt: wrapCreatedAt
        )
    }

    // MARK: - Message Unwrapping

    /// Unwraps a gift-wrapped message, returning the decrypted rumor
    ///
    /// - Parameters:
    ///   - giftWrap: The kind 1059 gift wrap event
    ///   - recipientKeypair: The recipient's keypair (must have private key)
    /// - Returns: The unwrapped rumor event, or nil on failure
    static func unwrap(
        giftWrap: NostrEvent,
        recipientKeypair: FullKeypair
    ) -> NostrEvent? {

        guard giftWrap.kind == NostrKind.gift_wrap.rawValue else {
            #if DEBUG
            print("[DM-DEBUG] unwrap: not a gift_wrap (kind \(giftWrap.kind))")
            #endif
            return nil
        }

        // Get wrap sender pubkey (ephemeral key)
        let wrapSenderPubkey = giftWrap.pubkey

        // Decrypt seal from gift wrap
        let sealJson: String
        do {
            sealJson = try NIP44v2Encryption.decrypt(
                payload: giftWrap.content,
                privateKeyA: recipientKeypair.privkey,
                publicKeyB: wrapSenderPubkey
            )
        } catch {
            #if DEBUG
            print("[DM-DEBUG] unwrap: seal decrypt FAILED: \(error)")
            #endif
            return nil
        }

        // Parse seal event
        guard let seal = NostrEvent.owned_from_json(json: sealJson) else {
            #if DEBUG
            print("[DM-DEBUG] unwrap: seal JSON parse FAILED")
            #endif
            return nil
        }

        guard seal.kind == NostrKind.seal.rawValue else {
            #if DEBUG
            print("[DM-DEBUG] unwrap: seal wrong kind \(seal.kind), expected 13")
            #endif
            return nil
        }

        // SECURITY: Verify seal signature to prevent spoofed sender pubkeys
        // Without this, an attacker could forge messages appearing to come from anyone
        guard validate_event(ev: seal) == .ok else {
            #if DEBUG
            print("[DM-DEBUG] unwrap: seal signature INVALID")
            #endif
            return nil
        }

        // Get real sender pubkey from seal (now trusted after signature verification)
        let senderPubkey = seal.pubkey

        // Decrypt rumor from seal
        let rumorJson: String
        do {
            rumorJson = try NIP44v2Encryption.decrypt(
                payload: seal.content,
                privateKeyA: recipientKeypair.privkey,
                publicKeyB: senderPubkey
            )
        } catch {
            #if DEBUG
            print("[DM-DEBUG] unwrap: rumor decrypt FAILED: \(error)")
            #endif
            return nil
        }

        // Parse rumor event - rumors may not have id field, so parse manually
        guard let rumor = parseRumorJson(rumorJson, senderPubkey: senderPubkey) else {
            #if DEBUG
            print("[DM-DEBUG] unwrap: rumor JSON parse FAILED, content: \(rumorJson.prefix(200))...")
            #endif
            return nil
        }

        // SECURITY: Verify rumor.pubkey matches seal.pubkey
        // Per NIP-17, the seal pubkey is the authoritative sender. If the rumor
        // contains a different pubkey, it could be an attempt to spoof the sender.
        guard rumor.pubkey == senderPubkey else {
            #if DEBUG
            print("[DM-DEBUG] unwrap: SECURITY - rumor pubkey mismatch (rumor: \(rumor.pubkey.hex().prefix(16)), seal: \(senderPubkey.hex().prefix(16)))")
            #endif
            return nil
        }

        // Rumors should be kind 14 (dm_chat) and unsigned
        guard rumor.kind == NostrKind.dm_chat.rawValue else {
            #if DEBUG
            print("[DM-DEBUG] unwrap: rumor wrong kind \(rumor.kind), expected 14")
            #endif
            return nil
        }

        #if DEBUG
        print("[DM-DEBUG] unwrap: SUCCESS rumor from:\(rumor.pubkey.npub.prefix(16)) content:'\(rumor.content.prefix(30))'")
        #endif
        return rumor
    }

    // MARK: - JSON Building

    /// Builds the JSON for an unsigned rumor event (kind 14)
    /// Per NIP-17: "A rumor is a regular nostr event, but is not signed"
    /// This means it needs an id (computed hash) but no signature
    private static func buildRumorJson(
        content: String,
        senderPubkey: Pubkey,
        tags: [[String]]
    ) -> String? {
        let createdAt = UInt32(Date().timeIntervalSince1970)
        let kind = NostrKind.dm_chat.rawValue

        // Compute the event id (SHA256 of serialized event per NIP-01)
        let eventId = calculate_event_id(
            pubkey: senderPubkey,
            created_at: createdAt,
            kind: kind,
            tags: tags,
            content: content
        )

        // Rumor has id but no signature
        let event: [String: Any] = [
            "id": eventId.hex(),
            "pubkey": senderPubkey.hex(),
            "created_at": createdAt,
            "kind": kind,
            "tags": tags,
            "content": content
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: event),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }

        return json
    }

    /// Builds the JSON for a signed seal event (kind 13)
    private static func buildSealJson(
        encryptedContent: String,
        sender: FullKeypair,
        createdAt: UInt32
    ) -> String? {
        // Seal has no tags, just the encrypted rumor as content
        guard let seal = NostrEvent(
            content: encryptedContent,
            keypair: sender.to_keypair(),
            kind: NostrKind.seal.rawValue,
            tags: [],
            createdAt: createdAt
        ) else {
            return nil
        }

        return event_to_json(ev: seal)
    }

    /// Builds the gift wrap event (kind 1059)
    private static func buildGiftWrap(
        encryptedContent: String,
        wrapKeys: FullKeypair,
        recipient: Pubkey,
        createdAt: UInt32
    ) -> NostrEvent? {
        // Gift wrap has only p-tag for recipient
        let tags: [[String]] = [["p", recipient.hex()]]

        return NostrEvent(
            content: encryptedContent,
            keypair: wrapKeys.to_keypair(),
            kind: NostrKind.gift_wrap.rawValue,
            tags: tags,
            createdAt: createdAt
        )
    }

    // MARK: - Timestamp Randomization

    /// Returns a randomized timestamp up to 2 days in the past
    /// This adds temporal privacy by obscuring when messages were actually sent
    private static func randomizedTimestamp() -> UInt32 {
        let maxSkewSeconds: UInt32 = 2 * 24 * 60 * 60 // 2 days
        let now = UInt32(Date().timeIntervalSince1970)
        let skew = UInt32.random(in: 0...maxSkewSeconds)
        return now - skew
    }

    // MARK: - DM Relay List (kind 10050)

    /// Creates a kind 10050 DM relay list event
    ///
    /// - Parameters:
    ///   - relays: List of relay URLs where DMs should be sent
    ///   - keypair: The user's keypair to sign the event
    /// - Returns: Signed kind 10050 event, or nil on failure
    static func createDMRelayList(relays: [RelayURL], keypair: Keypair) -> NostrEvent? {
        // Build relay tags: [["relay", "wss://..."], ["relay", "wss://..."]]
        let tags = relays.map { ["relay", $0.absoluteString] }

        return NostrEvent(
            content: "",
            keypair: keypair,
            kind: NostrKind.dm_relay_list.rawValue,
            tags: tags
        )
    }

    /// Extracts relay URLs from a kind 10050 DM relay list event
    ///
    /// - Parameter event: The kind 10050 event
    /// - Returns: List of relay URLs, or empty if invalid/none found
    static func parseDMRelayList(event: NostrEvent) -> [RelayURL] {
        guard event.kind == NostrKind.dm_relay_list.rawValue else {
            return []
        }

        var relays: [RelayURL] = []
        for tag in event.tags {
            guard tag.count >= 2,
                  tag[0].string() == "relay",
                  let url = RelayURL(tag[1].string()) else {
                continue
            }
            relays.append(url)
        }
        return relays
    }

    // MARK: - Rumor JSON Parsing

    /// Parses a rumor JSON that may not have an id field.
    /// NIP-17 rumors are unsigned events, and some implementations omit the id.
    /// We calculate the id ourselves if missing.
    ///
    /// - Parameters:
    ///   - json: The rumor JSON string
    ///   - senderPubkey: The sender's pubkey from the seal (used as fallback)
    /// - Returns: A NostrEvent representing the rumor, or nil on failure
    private static func parseRumorJson(_ json: String, senderPubkey: Pubkey) -> NostrEvent? {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        // Extract required fields
        guard let content = dict["content"] as? String,
              let kind = dict["kind"] as? Int,
              let createdAt = dict["created_at"] as? Int else {
            #if DEBUG
            print("[DM-DEBUG] parseRumorJson: missing required fields")
            #endif
            return nil
        }

        // Get pubkey - use from JSON if present, otherwise use seal sender
        let pubkeyHex = dict["pubkey"] as? String
        let pubkey: Pubkey
        if let hex = pubkeyHex, let pk = Pubkey(hex: hex) {
            pubkey = pk
        } else {
            pubkey = senderPubkey
        }

        // Parse tags
        let tagsArray = dict["tags"] as? [[String]] ?? []

        // Try standard parsing first (for rumors with id)
        if let event = NostrEvent.owned_from_json(json: json) {
            return event
        }

        // Calculate id if not present (NIP-01 event id = SHA256 of serialized event)
        let eventId = calculate_event_id(
            pubkey: pubkey,
            created_at: UInt32(createdAt),
            kind: UInt32(kind),
            tags: tagsArray,
            content: content
        )

        // Create event using keypair initializer with empty signature
        // We need to construct the event manually since it's unsigned
        let rumorJson: [String: Any] = [
            "id": eventId.hex(),
            "pubkey": pubkey.hex(),
            "created_at": createdAt,
            "kind": kind,
            "tags": tagsArray,
            "content": content,
            "sig": String(repeating: "0", count: 128) // Placeholder sig for parsing
        ]

        guard let rumorData = try? JSONSerialization.data(withJSONObject: rumorJson),
              let rumorJsonStr = String(data: rumorData, encoding: .utf8) else {
            return nil
        }

        return NostrEvent.owned_from_json(json: rumorJsonStr)
    }
}
