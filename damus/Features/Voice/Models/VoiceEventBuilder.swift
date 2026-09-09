import Foundation

/// NIP-808 authoring rules. Call off the main thread: targets and pending events are verified.
enum VoiceEventBuilder {
    /// Ignore marked source/mention references; retain explicit and legacy thread roots.
    static func replyTags(parent: NostrEvent, relay: String = "") -> [[String]] {
        let eventTags = parent.tags.strings().filter {
            $0.first == "e" && $0.count >= 2 && NoteId(hex: $0[1]) != nil
                && ($0.count < 4 || $0[3].isEmpty || ["root", "reply"].contains($0[3]))
                && !($0.count > 4 && $0[4] == "repost-source")
        }
        let marked = eventTags.filter { $0.count >= 4 && ["root", "reply"].contains($0[3]) }
        let root = marked.first(where: { $0[3] == "root" }) ?? (marked.isEmpty ? eventTags.first : nil)
        var tags: [[String]] = []
        if let root {
            var tag = ["e", root[1], root.count > 2 ? root[2] : "", "root"]
            if root.count > 4, Pubkey(hex: root[4]) != nil { tag.append(root[4]) }
            tags.append(tag)
        } else if eventTags.isEmpty {
            tags.append(["e", parent.id.hex(), relay, "root", parent.pubkey.hex()])
        }
        tags.append(["e", parent.id.hex(), relay, "reply", parent.pubkey.hex()])
        tags.append(["p", parent.pubkey.hex()])
        return tags
    }

    private static func payload(_ draft: VoiceDraft) throws -> (content: String, tags: [[String]]) {
        guard draft.version == 1, draft.takeID != nil, draft.pendingTakeID == nil,
              let text = draft.transcript?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              text.utf8.count <= 12_000, let receipt = draft.receipt,
              receipt.reference.sha256 == draft.sha256, receipt.size == draft.size, receipt.size > 0,
              let duration = draft.duration, duration.isFinite, duration > 0 else {
            throw VoiceFailure("The audio post is not ready to publish. Keep the composer open to finish it.")
        }
        let media = try VoiceMediaReference(url: receipt.reference.url, sha256: receipt.reference.sha256,
                                           mimeType: receipt.reference.mimeType, duration: duration)
        var tags = media.tags
        var content = text
        if let parent = try draft.context.target() {
            switch draft.context.kind {
            case .reply: tags += replyTags(parent: parent)
            case .quote:
                tags.append(["q", parent.id.hex(), "", parent.pubkey.hex()])
                tags.append(["p", parent.pubkey.hex()])
                content += "\n\nnostr:" + Bech32Object.encode(.nevent(NEvent(event: parent, relays: [])))
            case .post: break
            }
        }
        if let recipient = draft.context.recipient { tags.append(["p", recipient]) }
        let attachments = try (draft.attachments ?? VoicePostAttachments()).payload()
        for tag in attachments.tags where !tags.contains(tag) { tags.append(tag) }
        if !attachments.content.isEmpty { content += "\n\n" + attachments.content.joined(separator: "\n") }
        guard content.utf8.count <= 32_000 else { throw VoiceFailure("The transcript and attachments are too long for one post.") }
        _ = try VoiceMediaReference(tags: tags)
        return (content, tags)
    }

    /// Sign only complete finalized drafts; no local path or placeholder can enter a voice event.
    static func build(_ draft: VoiceDraft, keypair: FullKeypair, clientTag: [String]? = nil) throws -> NostrEvent {
        guard draft.context.account == keypair.pubkey.hex() else { throw VoiceFailure("The draft belongs to another account.") }
        let expected = try payload(draft)
        var tags = expected.tags
        if let clientTag, clientTag.first == "client" { tags.append(clientTag) }
        guard let event = NostrEvent(content: expected.content, keypair: keypair.to_keypair(),
                                     kind: NostrKind.voice.rawValue, tags: tags), event.verify() else {
            throw VoiceFailure("The voice post could not be signed.")
        }
        return event
    }

    /// Retries within the open composer reuse the exact signed JSON and all attachment fields.
    static func pendingEvent(_ draft: VoiceDraft) throws -> NostrEvent {
        guard let json = draft.eventJSON, let data = json.data(using: .utf8),
              let event = try? JSONDecoder().decode(NostrEvent.self, from: data),
              event.known_kind == .voice, !event.is_rumor, event.pubkey.hex() == draft.context.account,
              event.verify() else {
            throw VoiceFailure("The pending post could not be verified.")
        }
        let expected = try payload(draft)
        guard event.content == expected.content,
              event.tags.strings().filter({ $0.first != "client" }) == expected.tags else {
            throw VoiceFailure("The pending post does not match its recording, transcript, or original context.")
        }
        _ = try VoiceMediaReference(tags: event.tags.strings())
        return event
    }
}
