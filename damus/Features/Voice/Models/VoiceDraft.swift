import Foundation

/// Immutable account and public composition target for the lifetime of an open composer.
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

    /// Revalidate the captured target before signing; rumors must never become public targets.
    func target() throws -> NostrEvent? {
        guard VoiceMediaReference.isSHA256(account) else { throw VoiceFailure("The draft account is invalid.") }
        if let recipient, kind != .post || Pubkey(hex: recipient) == nil {
            throw VoiceFailure("The recipient is invalid.")
        }
        guard kind != .post else {
            guard targetID == nil, targetJSON == nil else { throw VoiceFailure("The post context is invalid.") }
            return nil
        }
        guard let targetJSON, let data = targetJSON.data(using: .utf8),
              let event = try? JSONDecoder().decode(NostrEvent.self, from: data),
              event.id.hex() == targetID, event.known_kind?.isPost == true,
              !event.is_rumor, event.verify() else {
            throw VoiceFailure("The original post could not be verified. Keep this composer open to retry.")
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

/// Delivery states distinguish a queued post from a relay's actual acceptance.
enum VoicePublicationPhase: String, Codable, Sendable {
    case draft, queued, dispatched, accepted, rejected, retryable
}

/// An open audio composition. Files are temporary and this value is never restored from disk.
struct VoiceDraft: Codable, Equatable, Sendable, Identifiable {
    var version = 1
    let id: UUID
    let context: VoiceContext
    var takeID: UUID?
    var pendingTakeID: UUID?
    var transcript: String?
    var attachments: VoicePostAttachments?
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

/// Owns temporary composition files and in-memory snapshots, never a saved-audio library.
/// All file access is serialized off the main actor. PostBox owns submitted network events.
actor VoiceDraftStore {
    static let shared = VoiceDraftStore()
    private let rootOverride: URL?
    private let legacyRootOverride: URL?
    private let session = UUID()
    private var prepared = false
    private var retiredAccounts: Set<String> = []
    private var owners: [String: UUID] = [:]
    private var compositions: [String: VoiceDraft] = [:]

    init(root: URL? = nil, legacyRoot: URL? = nil) {
        rootOverride = root
        legacyRootOverride = legacyRoot
    }

    private func ownershipKey(_ context: VoiceContext) -> String { context.account + ":" + context.key }

    /// A replacement composer cannot acquire files while the previous writer is closing.
    func acquire(context: VoiceContext) async throws -> VoiceDraftLease {
        let key = ownershipKey(context)
        while owners[key] != nil { try await Task.sleep(nanoseconds: 100_000_000) }
        try Task.checkCancellation()
        try retireLegacyDrafts(account: context.account)
        let id = UUID()
        owners[key] = id
        compositions.removeValue(forKey: key)
        return VoiceDraftLease(id: id, context: context, store: self)
    }

    func release(context: VoiceContext, owner: UUID) {
        let key = ownershipKey(context)
        guard owners[key] == owner else { return }
        // Normal close has already deleted the directory. Also clean up an abandoned lease.
        do {
            let directory = try directory(context)
            try FileManager.default.removeItem(at: directory)
        } catch {
            Log.error("Could not remove abandoned audio files: %s", for: .networking, error.localizedDescription)
        }
        compositions.removeValue(forKey: key)
        owners.removeValue(forKey: key)
    }

    private func requireOwner(_ lease: VoiceDraftLease, context: VoiceContext) throws {
        guard ownershipKey(lease.context) == ownershipKey(context),
              owners[ownershipKey(context)] == lease.id else { throw CancellationError() }
    }

    private func directory(_ context: VoiceContext) throws -> URL {
        guard VoiceMediaReference.isSHA256(context.account) else { throw VoiceFailure("The composition account is invalid.") }
        let base = rootOverride ?? FileManager.default.temporaryDirectory.appendingPathComponent("VoiceCompositions-v2", isDirectory: true)
        if !prepared {
            // The app's singleton is the sole owner of this temporary root. No restart recovery.
            if rootOverride == nil, FileManager.default.fileExists(atPath: base.path) {
                try FileManager.default.removeItem(at: base)
            }
            prepared = true
        }
        let directory = base.appendingPathComponent(session.uuidString, isDirectory: true)
            .appendingPathComponent(context.account, isDirectory: true)
            .appendingPathComponent(VoiceAudioFiles.digest(Data(context.key.utf8)), isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
                                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        return directory
    }

    func file(for take: UUID, context: VoiceContext) throws -> URL {
        try directory(context).appendingPathComponent(take.uuidString + ".m4a")
    }

    /// Photos use the same owned directory as the recording, so discard removes both.
    func photoFile(for id: UUID, context: VoiceContext) throws -> URL {
        try directory(context).appendingPathComponent(id.uuidString + ".jpg")
    }

    func removePhoto(_ id: UUID, context: VoiceContext) throws {
        let file = try photoFile(for: id, context: context)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }

    /// Only a live composer can load its own in-memory snapshot; a new store always starts empty.
    func load(context: VoiceContext) -> VoiceDraft? { compositions[ownershipKey(context)] }

    /// Retire only the old format's unpublished local audio, without following arbitrary paths.
    private func retireLegacyDrafts(account: String) throws {
        guard !retiredAccounts.contains(account), rootOverride == nil || legacyRootOverride != nil else { return }
        guard VoiceMediaReference.isSHA256(account) else { throw VoiceFailure("The composition account is invalid.") }
        let base = try legacyRootOverride ?? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: false)
            .appendingPathComponent("VoiceDrafts-v1", isDirectory: true)
        if FileManager.default.fileExists(atPath: base.path) {
            guard try base.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { return }
        }
        let root = base.appendingPathComponent(account, isDirectory: true)
        if FileManager.default.fileExists(atPath: root.path) {
            guard try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { return }
            for folder in try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
                guard VoiceMediaReference.isSHA256(folder.lastPathComponent),
                      try folder.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else { continue }
                let manifest = folder.appendingPathComponent("draft.json")
                if FileManager.default.fileExists(atPath: manifest.path) {
                    let values = try manifest.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
                    guard values.isSymbolicLink != true, (values.fileSize ?? 0) <= 1024 * 1024 else { continue }
                    // An unreadable legacy record cannot safely be classified as unpublished.
                    guard let previous = try? JSONDecoder().decode(VoiceDraft.self, from: Data(contentsOf: manifest)),
                          previous.context.account == account, previous.eventJSON == nil else { continue }
                }
                try FileManager.default.removeItem(at: folder)
            }
        }
        retiredAccounts.insert(account)
    }

    /// Merge delivery updates without permitting edits to an already signed event.
    @discardableResult
    func save(_ draft: VoiceDraft, lease: VoiceDraftLease) throws -> VoiceDraft {
        try requireOwner(lease, context: draft.context)
        var saved = draft
        if let current = load(context: draft.context) {
            guard current.id == draft.id, current.context == draft.context else { throw CancellationError() }
            if current.eventJSON != nil {
                guard current.eventJSON == draft.eventJSON, current.takeID == draft.takeID,
                      current.pendingTakeID == nil, draft.pendingTakeID == nil,
                      current.receipt == draft.receipt, current.sha256 == draft.sha256,
                      current.size == draft.size, current.duration == draft.duration,
                      current.locale == draft.locale, current.transcript == draft.transcript,
                      current.attachments == draft.attachments else {
                    throw VoiceFailure("This recording already belongs to a signed post. Retry that same post.")
                }
                saved.phase = current.phase
                saved.relayResults = current.relayResults
                saved.acceptedRelays = current.acceptedRelays
                saved.lastError = current.lastError
            }
        }
        saved.updatedAt = Date()
        compositions[ownershipKey(saved.context)] = saved
        return saved
    }

    /// Check the current composition before handing its exact event to PostBox.
    func requireCurrentEvent(_ draft: VoiceDraft) throws {
        guard let current = load(context: draft.context), current.id == draft.id,
              current.eventJSON != nil, current.eventJSON == draft.eventJSON,
              current.takeID == draft.takeID, current.receipt == draft.receipt else {
            throw VoiceFailure("This post no longer belongs to the open composer.")
        }
    }

    /// A late ACK may update this open composition, but cannot recreate a closed or newer one.
    func recordDelivery(_ update: PostBoxDelivery, for sent: VoiceDraft) throws {
        guard var current = load(context: sent.context), current.id == sent.id,
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
                current.lastError = "A relay rejected this post. Retry from this composer."
            }
        case .noRelays:
            if current.acceptedRelays.isEmpty {
                current.phase = .retryable
                current.lastError = "No publishing relays are configured. Add a write relay to deliver this post."
            }
        }
        current.updatedAt = Date()
        compositions[ownershipKey(current.context)] = current
    }

    /// Delete a replaced take only after the current composition no longer references it.
    func removeTake(_ take: UUID, context: VoiceContext) throws {
        if let draft = load(context: context), draft.takeID == take || draft.pendingTakeID == take { return }
        let url = try file(for: take, context: context)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    /// Remove local composition files only. This never retracts an event already sent to relays.
    func discard(_ draft: VoiceDraft, lease: VoiceDraftLease) throws {
        try requireOwner(lease, context: draft.context)
        if let current = load(context: draft.context), current.id != draft.id { throw CancellationError() }
        let directory = try directory(draft.context)
        try FileManager.default.removeItem(at: directory)
        compositions.removeValue(forKey: ownershipKey(draft.context))
    }
}
