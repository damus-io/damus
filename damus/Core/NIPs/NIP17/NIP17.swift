//
//  NIP17.swift
//  damus
//
//  Created by OpenAI Codex on 2025-02-14.
//

import Foundation

enum NIP17Error: Error {
    case missingRecipientKey
    case sealDecodingFailed
    case invalidSealKind(UInt32)
    case invalidMessageKind(UInt32)
    case sealVerificationFailed
    case sealPubkeyMismatch
    case messageDecodingFailed
    case encryptionFailed
    case decryptionFailed
    case missingSenderPrivkey
    case emptyRecipientList
}

struct NIP17UnsignedEvent: Codable {
    let id: NoteId
    let pubkey: Pubkey
    let created_at: UInt32
    let kind: UInt32
    let tags: [[String]]
    let content: String
    let sig: String?

    init(id: NoteId, pubkey: Pubkey, created_at: UInt32, kind: UInt32, tags: [[String]], content: String) {
        self.id = id
        self.pubkey = pubkey
        self.created_at = created_at
        self.kind = kind
        self.tags = tags
        self.content = content
        self.sig = nil
    }
}

struct NIP17DecryptedMessage {
    let message: NIP17UnsignedEvent
    let seal: NostrEvent
    let giftwrap: NostrEvent
}

struct NIP17WrapResult {
    let unsigned: NIP17UnsignedEvent
    let seals: [Pubkey: NostrEvent]
    let wraps: [Pubkey: NostrEvent]
}

enum NIP17 {
    static func randomTimestampWithinTwoDays(now: Date = .init()) -> UInt32 {
        let nowSeconds = UInt32(now.timeIntervalSince1970)
        let twoDays: UInt32 = 2 * 24 * 60 * 60
        let offset = UInt32.random(in: 0...twoDays)
        return nowSeconds &- offset
    }

    /// Produces the unsigned kind 14 event payload for the provided inputs.
    static func makeUnsignedMessage(content: String,
                                    sender: Pubkey,
                                    recipients: [Pubkey],
                                    tags extraTags: [[String]] = [],
                                    createdAt: UInt32 = UInt32(Date().timeIntervalSince1970),
                                    kind: NostrKind = .dmChat17) -> NIP17UnsignedEvent {
        var tags = extraTags
        for recipient in recipients {
            if !tags.contains(where: { tag in tag.first == "p" && tag.dropFirst().first == recipient.hex() }) {
                tags.append(["p", recipient.hex()])
            }
        }

        let eventId = calculate_event_id(pubkey: sender,
                                         created_at: createdAt,
                                         kind: kind.rawValue,
                                         tags: tags,
                                         content: content)

        return .init(id: eventId,
                     pubkey: sender,
                     created_at: createdAt,
                     kind: kind.rawValue,
                     tags: tags,
                     content: content)
    }

    static func encodeUnsignedEvent(_ event: NIP17UnsignedEvent) throws -> String {
        try encode_json_data(event).utf8String()
    }

    static func decodeUnsignedEvent(_ json: String) throws -> NIP17UnsignedEvent {
        try decode_json_throwing(json)
    }

    /// Wrap a plaintext message into per-recipient gift wraps (kind 1059).
    static func wrapMessage(content: String,
                            recipients: [Pubkey],
                            sender: FullKeypair,
                            subject: String? = nil,
                            additionalTags: [[String]] = [],
                            createdAt: UInt32 = UInt32(Date().timeIntervalSince1970),
                            replyTag: [String]? = nil,
                            messageKind: NostrKind = .dmChat17,
                            now: Date = .init()) throws -> NIP17WrapResult {
        guard !recipients.isEmpty else {
            throw NIP17Error.emptyRecipientList
        }

        var tags = additionalTags
        if let replyTag {
            tags.append(replyTag)
        }
        if let subject {
            tags.append(["subject", subject])
        }

        var uniqueRecipients: [Pubkey] = []
        var seenRecipients = Set<Pubkey>()

        for recipient in recipients {
            if seenRecipients.insert(recipient).inserted {
                uniqueRecipients.append(recipient)
            }
        }

        if seenRecipients.insert(sender.pubkey).inserted {
            uniqueRecipients.append(sender.pubkey)
        }

        let unsignedMessage = makeUnsignedMessage(content: content,
                                                  sender: sender.pubkey,
                                                  recipients: uniqueRecipients,
                                                  tags: tags,
                                                  createdAt: createdAt,
                                                  kind: messageKind)

        let messageJSON = try encodeUnsignedEvent(unsignedMessage)
        let envelopeMap = try createGiftWraps(messageJSON: messageJSON,
                                              sender: sender,
                                              recipients: uniqueRecipients,
                                              now: now)

        let seals = Dictionary(uniqueKeysWithValues: envelopeMap.map { ($0.key, $0.value.seal) })
        let wraps = Dictionary(uniqueKeysWithValues: envelopeMap.map { ($0.key, $0.value.wrap) })

        return NIP17WrapResult(unsigned: unsignedMessage, seals: seals, wraps: wraps)
    }

    /// Create gift wraps for the provided message JSON.
    static func createGiftWraps(messageJSON: String,
                                sender: FullKeypair,
                                recipients: [Pubkey],
                                now: Date = .init()) throws -> [Pubkey: (wrap: NostrEvent, seal: NostrEvent)] {
        var results: [Pubkey: (wrap: NostrEvent, seal: NostrEvent)] = [:]

        let sealContent = try recipients.reduce(into: [Pubkey: (cipher: String, sealEvent: NostrEvent)]()) { acc, recipient in
            let cipher = try NIP44v2Encryption.encrypt(plaintext: messageJSON,
                                                       privateKeyA: sender.privkey,
                                                       publicKeyB: recipient)
            let sealTimestamp = randomTimestampWithinTwoDays(now: now)
            guard let sealEvent = NostrEvent(content: cipher,
                                             keypair: sender.to_keypair(),
                                             kind: NostrKind.dmSeal.rawValue,
                                             tags: [],
                                             createdAt: sealTimestamp) else {
                throw NIP17Error.encryptionFailed
            }
            acc[recipient] = (cipher, sealEvent)
        }

        for recipient in recipients {
            guard let entry = sealContent[recipient] else {
                throw NIP17Error.encryptionFailed
            }

            let sealJSON = event_to_json(ev: entry.sealEvent)
            let randomKey = generate_new_keypair()
            let wrapCipher = try NIP44v2Encryption.encrypt(plaintext: sealJSON,
                                                           privateKeyA: randomKey.privkey,
                                                           publicKeyB: recipient)

            var tags: [[String]] = [["p", recipient.hex()]]
            // The spec allows optional relay URLs, which we can add later.

            let wrapTimestamp = randomTimestampWithinTwoDays(now: now)
            guard let wrapEvent = NostrEvent(content: wrapCipher,
                                             keypair: randomKey.to_keypair(),
                                             kind: NostrKind.dmGiftWrap.rawValue,
                                             tags: tags,
                                             createdAt: wrapTimestamp) else {
                throw NIP17Error.encryptionFailed
            }

            results[recipient] = (wrap: wrapEvent, seal: entry.sealEvent)
        }

        return results
    }

    /// Decrypt a gift wrap event (kind 1059) for a specific recipient keypair.
    static func unwrapGiftWrap(_ giftwrap: NostrEvent,
                               recipientPrivkey: Privkey,
                               now: Date = .init()) throws -> NIP17DecryptedMessage {
        guard giftwrap.known_kind == .dmGiftWrap else {
            throw NIP17Error.invalidSealKind(giftwrap.kind)
        }

        let decryptedSealJSON: String
        do {
            decryptedSealJSON = try NIP44v2Encryption.decrypt(payload: giftwrap.content,
                                                              privateKeyA: recipientPrivkey,
                                                              publicKeyB: giftwrap.pubkey)
        } catch {
            throw NIP17Error.decryptionFailed
        }

        guard let sealEvent = decode_nostr_event_json(json: decryptedSealJSON) else {
            throw NIP17Error.sealDecodingFailed
        }

        guard sealEvent.kind == NostrKind.dmSeal.rawValue else {
            throw NIP17Error.invalidSealKind(sealEvent.kind)
        }

        guard validate_event(ev: sealEvent) == .ok else {
            throw NIP17Error.sealVerificationFailed
        }

        let decryptedMessageJSON: String
        do {
            decryptedMessageJSON = try NIP44v2Encryption.decrypt(payload: sealEvent.content,
                                                                 privateKeyA: recipientPrivkey,
                                                                 publicKeyB: sealEvent.pubkey)
        } catch {
            throw NIP17Error.decryptionFailed
        }

        guard let message = try? decodeUnsignedEvent(decryptedMessageJSON) else {
            throw NIP17Error.messageDecodingFailed
        }

        guard message.pubkey == sealEvent.pubkey else {
            throw NIP17Error.sealPubkeyMismatch
        }

        guard message.kind == NostrKind.dmChat17.rawValue || message.kind == NostrKind.dmFile17.rawValue else {
            throw NIP17Error.invalidMessageKind(message.kind)
        }

        return NIP17DecryptedMessage(message: message, seal: sealEvent, giftwrap: giftwrap)
    }

    static func makeDisplayEvent(from message: NIP17UnsignedEvent) -> NostrEvent? {
        NdbNote.makeUnsigned(content: message.content,
                             pubkey: message.pubkey,
                             kind: message.kind,
                             tags: message.tags,
                             createdAt: message.created_at,
                             id: message.id)
    }
}

private extension Data {
    func utf8String() throws -> String {
        guard let string = String(data: self, encoding: .utf8) else {
            throw NIP17Error.encryptionFailed
        }
        return string
    }
}
