import XCTest
@testable import damus

final class VoiceDraftStoreTests: XCTestCase {
    private func root() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    private func fixture(published: Bool = false) throws -> VoiceDraft {
        let keys = generate_new_keypair()
        let context = VoiceContext(account: keys.pubkey.hex(), kind: .post, targetID: nil, targetJSON: nil)
        var draft = VoiceDraft(context: context, locale: "en-US")
        draft.takeID = UUID()
        draft.transcript = "The same recording must survive every retry."
        draft.duration = 1.25
        draft.sha256 = VoiceAudioFiles.digest(Data("take bytes".utf8))
        draft.size = Data("take bytes".utf8).count
        let reference = try VoiceMediaReference(url: "https://blossom.band/opaque?receipt=original",
                                               sha256: draft.sha256!, mimeType: "audio/mp4", duration: 1.25)
        draft.receipt = VoiceUploadReceipt(server: "https://blossom.band", reference: reference, size: draft.size!)
        if published {
            let event = try XCTUnwrap(NostrEvent(content: draft.transcript!, keypair: keys.to_keypair(), kind: 1808, tags: reference.tags))
            draft.eventJSON = event_to_json(ev: event)
            draft.phase = .queued
        }
        return draft
    }

    func testRestartRetainsAudioReceiptAndExactSignedEvent() async throws {
        let root = try root()
        let store = VoiceDraftStore(root: root)
        let draft = try fixture(published: true)
        let lease = try await store.acquire(context: draft.context)
        let audio = try await store.file(for: draft.takeID!, context: draft.context)
        try Data("take bytes".utf8).write(to: audio)
        let saved = try await store.save(draft, lease: lease)
        try await store.recordDelivery(.noRelays, for: saved)
        let reopened = VoiceDraftStore(root: root)
        let restored = try await reopened.load(context: draft.context)
        XCTAssertEqual(restored?.eventJSON, saved.eventJSON)
        XCTAssertEqual(restored?.receipt, saved.receipt)
        XCTAssertEqual(restored?.phase, .retryable)
        XCTAssertEqual(try Data(contentsOf: audio), Data("take bytes".utf8))
        let inventory = try await reopened.inventory(account: draft.context.account)
        XCTAssertEqual(inventory.drafts.map(\.id), [draft.id])
        let otherAccount = try await reopened.inventory(account: String(repeating: "b", count: 64))
        XCTAssertTrue(otherAccount.drafts.isEmpty)
    }

    func testStaleComposerSaveCannotEraseAcceptanceOrTreatRejectionAsSuccess() async throws {
        let store = VoiceDraftStore(root: try root())
        let draft = try fixture(published: true)
        let lease = try await store.acquire(context: draft.context)
        let stale = try await store.save(draft, lease: lease)
        let relay = try XCTUnwrap(RelayURL("wss://relay.example"))
        try await store.recordDelivery(.dispatched(relay), for: stale)
        var current = try await store.load(context: draft.context)
        XCTAssertEqual(current?.phase, .dispatched)
        XCTAssertTrue(current?.acceptedRelays.isEmpty == true)
        try await store.recordDelivery(.rejected(relay, "blocked"), for: stale)
        current = try await store.load(context: draft.context)
        XCTAssertEqual(current?.phase, .rejected)
        XCTAssertTrue(current?.acceptedRelays.isEmpty == true)
        try await store.recordDelivery(.accepted(relay), for: stale)
        let merged = try await store.save(stale, lease: lease)
        XCTAssertEqual(merged.phase, .accepted)
        XCTAssertEqual(merged.acceptedRelays, [relay.absoluteString])
        try await store.recordDelivery(.noRelays, for: stale)
        current = try await store.load(context: draft.context)
        XCTAssertEqual(current?.phase, .accepted)
    }

    func testOldAcknowledgementCannotMutateAReplacementDraft() async throws {
        let store = VoiceDraftStore(root: try root())
        let old = try fixture(published: true)
        let lease = try await store.acquire(context: old.context)
        try await store.save(old, lease: lease)
        let relay = try XCTUnwrap(RelayURL("wss://relay.example"))
        try await store.recordDelivery(.accepted(relay), for: old)
        try await store.discard(old, lease: lease)
        let replacement = VoiceDraft(context: old.context, locale: "en-US")
        try await store.save(replacement, lease: lease)
        try await store.recordDelivery(.rejected(relay, "late rejection"), for: old)
        let current = try await store.load(context: old.context)
        XCTAssertEqual(current?.id, replacement.id)
        XCTAssertEqual(current?.phase, .draft)
        XCTAssertTrue(current?.relayResults.isEmpty == true)
    }

    func testAReplacementTakeKeepsThePreviousFileUntilTheNewManifestIsSaved() async throws {
        let store = VoiceDraftStore(root: try root())
        var draft = try fixture()
        let lease = try await store.acquire(context: draft.context)
        let original = draft.takeID!
        let originalURL = try await store.file(for: original, context: draft.context)
        try Data("take bytes".utf8).write(to: originalURL)
        try await store.save(draft, lease: lease)
        let pending = UUID()
        draft.pendingTakeID = pending
        try await store.save(draft, lease: lease)
        try await store.removeTake(original, context: draft.context)
        XCTAssertTrue(FileManager.default.fileExists(atPath: originalURL.path))
        let pendingURL = try await store.file(for: pending, context: draft.context)
        try Data("new take".utf8).write(to: pendingURL)
        draft.takeID = pending
        draft.pendingTakeID = nil
        draft.receipt = nil
        try await store.save(draft, lease: lease)
        try await store.removeTake(original, context: draft.context)
        XCTAssertFalse(FileManager.default.fileExists(atPath: originalURL.path))
        XCTAssertEqual(try Data(contentsOf: pendingURL), Data("new take".utf8))
    }

    func testPendingPublicationCannotBeDiscarded() async throws {
        let store = VoiceDraftStore(root: try root())
        let draft = try fixture(published: true)
        let lease = try await store.acquire(context: draft.context)
        try await store.save(draft, lease: lease)
        do { try await store.discard(draft, lease: lease); XCTFail("Pending publication was deleted") }
        catch is VoiceFailure {}
        let restored = try await store.load(context: draft.context)
        XCTAssertEqual(restored?.eventJSON, draft.eventJSON)
    }

    func testAReleasedLeaseCannotWriteAfterAnotherComposerAcquiresTheContext() async throws {
        let store = VoiceDraftStore(root: try root())
        let draft = try fixture()
        let first = try await store.acquire(context: draft.context)
        try await store.save(draft, lease: first)
        let started = expectation(description: "second composer attempts ownership")
        let waiting = Task {
            started.fulfill()
            return try await store.acquire(context: draft.context)
        }
        await fulfillment(of: [started], timeout: 1)
        for _ in 0..<10 { await Task.yield() }
        waiting.cancel()
        do { _ = try await waiting.value; XCTFail("Two composers owned the same context") }
        catch is CancellationError {}
        await store.release(context: draft.context, owner: first.id)
        let second = try await store.acquire(context: draft.context)
        do { try await store.save(draft, lease: first); XCTFail("A stale composer overwrote the draft") }
        catch is CancellationError {}
        try await store.save(draft, lease: second)
    }
}
