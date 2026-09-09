import Foundation

/// Immutable account and public composition target. Target JSON permits restart without a cached parent.
struct VoiceContext: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case post, reply, quote }
    let account: String
    let kind: Kind
    let targetID: String?
    let targetJSON: String?
    let recipient: String?

    init(account: String, kind: Kind, targetID: String?, targetJSON: String?, recipient: String? = nil) {
        self.account = account; self.kind = kind; self.targetID = targetID
        self.targetJSON = targetJSON; self.recipient = recipient
    }

    var key: String { kind.rawValue + (targetID.map { ":" + $0 } ?? "") + (recipient.map { ":p:" + $0 } ?? "") }

    /// Revalidate saved context before signing; local JSON cannot turn a rumor into a public target.
    func target() throws -> NostrEvent? {
        guard VoiceMediaReference.isSHA256(account) else { throw VoiceFailure("The draft account is invalid.") }
        if let recipient, kind != .post || Pubkey(hex: recipient) == nil {
            throw VoiceFailure("The saved recipient is invalid.")
        }
        guard kind != .post else {
            guard targetID == nil, targetJSON == nil else { throw VoiceFailure("The saved post context is invalid.") }
            return nil
        }
        guard let targetJSON, let data = targetJSON.data(using: .utf8),
              let event = try? JSONDecoder().decode(NostrEvent.self, from: data),
              event.id.hex() == targetID, event.known_kind?.isPost == true,
              !event.is_rumor, event.verify() else {
            throw VoiceFailure("The original post could not be verified. Your recording is still saved.")
        }
        return event
    }
}

/// A validated receipt binds a single primary server's exact URL to the finalized take bytes.
struct VoiceUploadReceipt: Codable, Equatable, Sendable {
    let server: String
    let reference: VoiceMediaReference
    let size: Int
}

/// Durable states describe what is known, not an optimistic UI send state.
enum VoicePublicationPhase: String, Codable, Sendable {
    case draft, queued, dispatched, accepted, rejected, retryable
}

/// Versioned local state; paths are derived from UUIDs and never included in signed events.
struct VoiceDraft: Codable, Equatable, Sendable, Identifiable {
    var version = 1
    let id: UUID
    let context: VoiceContext
    var takeID: UUID?
    var pendingTakeID: UUID?
    var transcript: String?
    var locale: String
    var duration: TimeInterval?
    var sha256: String?
    var size: Int?
    var receipt: VoiceUploadReceipt?
    var eventJSON: String?
    var phase: VoicePublicationPhase = .draft
    var relayResults: [String: String] = [:]
    var acceptedRelays: Set<String> = []
    var lastError: String?
    var updatedAt = Date()

    init(context: VoiceContext, locale: String) {
        self.id = UUID()
        self.context = context
        self.locale = locale
    }
}

/// Account lifetime fencing is synchronous so closing an account invalidates callbacks immediately.
final class VoiceAccountLifetime: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    var isActive: Bool { lock.lock(); defer { lock.unlock() }; return active }
    func invalidate() { lock.lock(); active = false; lock.unlock() }
}

/// Exclusive ownership lasts until the sheet's last asynchronous operation has finished.
final class VoiceDraftLease: Sendable {
    let id: UUID
    let context: VoiceContext
    private let store: VoiceDraftStore

    init(id: UUID, context: VoiceContext, store: VoiceDraftStore) {
        self.id = id; self.context = context; self.store = store
    }

    deinit {
        let store = store, context = context, id = id
        Task { await store.release(context: context, owner: id) }
    }
}

/// Durable recording/draft ownership. All filesystem operations run off the main actor.
actor VoiceDraftStore {
    private var owners: [String: UUID] = [:]

    private func ownershipKey(_ context: VoiceContext) -> String { context.account + ":" + context.key }

    /// A reopening sheet waits for the previous writer/upload callback before reading its files.
    func acquire(context: VoiceContext) async throws -> VoiceDraftLease {
        let key = ownershipKey(context)
        while owners[key] != nil { try await Task.sleep(nanoseconds: 100_000_000) }
        try Task.checkCancellation()
        let id = UUID()
        owners[key] = id
        return VoiceDraftLease(id: id, context: context, store: self)
    }

    func release(context: VoiceContext, owner: UUID) {
        let key = ownershipKey(context)
        if owners[key] == owner { owners.removeValue(forKey: key) }
    }

    private func requireOwner(_ lease: VoiceDraftLease, context: VoiceContext) throws {
        guard ownershipKey(lease.context) == ownershipKey(context),
              owners[ownershipKey(context)] == lease.id else { throw CancellationError() }
    }
    static let shared = VoiceDraftStore()
    private let rootOverride: URL?
    init(root: URL? = nil) { rootOverride = root }

    private func directory(_ context: VoiceContext) throws -> URL {
        guard VoiceMediaReference.isSHA256(context.account) else { throw VoiceFailure("The draft account is invalid.") }
        let base: URL
        if let rootOverride { base = rootOverride }
        else {
            base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("VoiceDrafts-v1", isDirectory: true)
        }
        let directory = base.appendingPathComponent(context.account, isDirectory: true)
            .appendingPathComponent(VoiceAudioFiles.digest(Data(context.key.utf8)), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        var excluded = directory
        var resources = URLResourceValues()
        resources.isExcludedFromBackup = true
        try excluded.setResourceValues(resources)
        return directory
    }

    func file(for take: UUID, context: VoiceContext) throws -> URL {
        try directory(context).appendingPathComponent(take.uuidString + ".m4a")
    }

    func load(context: VoiceContext) throws -> VoiceDraft? {
        let url = try directory(context).appendingPathComponent("draft.json")
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let draft = try readManifest(url)
        guard draft.context.account == context.account, draft.context.key == context.key else {
            throw VoiceFailure("The saved voice draft belongs to a different account or post.")
        }
        return draft
    }

    private func readManifest(_ url: URL) throws -> VoiceDraft {
        guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) <= 1024 * 1024 else {
            throw VoiceFailure("The saved voice draft is too large to load safely.")
        }
        let draft = try JSONDecoder().decode(VoiceDraft.self, from: Data(contentsOf: url))
        guard draft.version == 1 else { throw VoiceFailure("This voice draft requires a newer app version.") }
        return draft
    }

    struct Inventory: Sendable {
        var drafts: [VoiceDraft] = []
        var unreadableCount = 0
    }

    /// List manifests only. Opening a take still requires exclusive ownership and verification.
    func inventory(account: String) throws -> Inventory {
        let context = VoiceContext(account: account, kind: .post, targetID: nil, targetJSON: nil)
        let accountDirectory = try directory(context).deletingLastPathComponent()
        let folders = try FileManager.default.contentsOfDirectory(at: accountDirectory, includingPropertiesForKeys: nil)
        var result = Inventory()
        for folder in folders where VoiceMediaReference.isSHA256(folder.lastPathComponent) {
            try Task.checkCancellation()
            let manifest = folder.appendingPathComponent("draft.json")
            guard FileManager.default.fileExists(atPath: manifest.path) else { continue }
            do {
                let draft = try readManifest(manifest)
                guard draft.context.account == account,
                      VoiceAudioFiles.digest(Data(draft.context.key.utf8)) == folder.lastPathComponent else {
                    throw VoiceFailure("The saved draft's account or context is invalid.")
                }
                if draft.takeID != nil || draft.pendingTakeID != nil || draft.eventJSON != nil { result.drafts.append(draft) }
            } catch { result.unreadableCount += 1 }
        }
        result.drafts.sort { $0.updatedAt > $1.updatedAt }
        return result
    }

    /// Only the active composer may change a take. Relay status is merged independently.
    @discardableResult
    func save(_ draft: VoiceDraft, lease: VoiceDraftLease) throws -> VoiceDraft {
        try requireOwner(lease, context: draft.context)
        var saved = draft
        if let current = try load(context: draft.context) {
            guard current.id == draft.id, current.context == draft.context else { throw CancellationError() }
            if current.eventJSON != nil {
                guard current.eventJSON == draft.eventJSON, current.takeID == draft.takeID,
                      current.pendingTakeID == nil, draft.pendingTakeID == nil,
                      current.receipt == draft.receipt, current.sha256 == draft.sha256,
                      current.size == draft.size, current.duration == draft.duration,
                      current.locale == draft.locale, current.transcript == draft.transcript else {
                    throw VoiceFailure("This recording already belongs to a signed post. Retry its saved event.")
                }
                saved.phase = current.phase
                saved.relayResults = current.relayResults
                saved.acceptedRelays = current.acceptedRelays
                saved.lastError = current.lastError
            }
        }
        saved.updatedAt = Date()
        try write(saved)
        return saved
    }

    private func write(_ draft: VoiceDraft) throws {
        let data = try JSONEncoder().encode(draft)
        guard data.count <= 1024 * 1024 else { throw VoiceFailure("The voice draft exceeds the local storage limit.") }
        try data.write(to: directory(draft.context).appendingPathComponent("draft.json"),
                       options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    /// Publication can use only an event that already has durable ownership; it cannot overwrite it.
    func requireSavedEvent(_ draft: VoiceDraft) throws {
        guard let current = try load(context: draft.context), current.id == draft.id,
              current.eventJSON != nil, current.eventJSON == draft.eventJSON,
              current.takeID == draft.takeID, current.receipt == draft.receipt else {
            throw VoiceFailure("The signed post is not saved. Keep this recording and retry.")
        }
    }

    /// ACK callbacks remain valid after dismissal, but cannot affect a replacement draft.
    func recordDelivery(_ update: PostBoxDelivery, for sent: VoiceDraft) throws {
        guard var current = try load(context: sent.context), current.id == sent.id,
              current.eventJSON != nil, current.eventJSON == sent.eventJSON,
              current.takeID == sent.takeID else { return }
        switch update {
        case .queued:
            if current.acceptedRelays.isEmpty { current.phase = .queued }
        case .dispatched(let relay):
            if current.relayResults[relay.absoluteString] == nil { current.relayResults[relay.absoluteString] = "Waiting for acknowledgement" }
            if current.acceptedRelays.isEmpty, current.phase != .rejected { current.phase = .dispatched }
        case .accepted(let relay):
            current.acceptedRelays.insert(relay.absoluteString)
            current.relayResults[relay.absoluteString] = "Accepted"
            current.phase = .accepted
            current.lastError = nil
        case .rejected(let relay, let message):
            current.relayResults[relay.absoluteString] = "Rejected: " + String(message.prefix(500))
            if current.acceptedRelays.isEmpty {
                current.phase = .rejected
                current.lastError = "A relay rejected this post. The recording and signed post are saved for retry."
            }
        case .noRelays:
            if current.acceptedRelays.isEmpty {
                current.phase = .retryable
                current.lastError = "No publishing relays are configured. Add a write relay, then retry this saved post."
            }
        }
        current.updatedAt = Date()
        try write(current)
    }

    /// Delete only this draft's unowned take after a replacement manifest has landed.
    func removeTake(_ take: UUID, context: VoiceContext) throws {
        if let draft = try load(context: context), draft.takeID == take || draft.pendingTakeID == take { return }
        let url = try file(for: take, context: context)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    /// Explicit discard refuses an event awaiting relay delivery; cancel that delivery first.
    func discard(_ draft: VoiceDraft, lease: VoiceDraftLease) throws {
        try requireOwner(lease, context: draft.context)
        let directory = try directory(draft.context)
        guard let current = try load(context: draft.context), current.id == draft.id else { return }
        guard current.eventJSON == nil || current.phase == .accepted else {
            throw VoiceFailure("This recording belongs to a pending post. Keep it until delivery is resolved.")
        }
        try FileManager.default.removeItem(at: directory)
    }
}
