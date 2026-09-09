import Foundation

/// Keeps publication testable without real relays or real posts.
protocol VoicePublishing: Sendable {
    func publish(_ draft: VoiceDraft, state: DamusState) async throws
}

/// The manifest owns the exact signed event before any relay handoff. Reopening the Audio
/// composer can retry that event after restart without uploading its bytes again.
actor VoicePublisher: VoicePublishing {
    let store: VoiceDraftStore
    init(store: VoiceDraftStore = .shared) { self.store = store }

    func publish(_ draft: VoiceDraft, state: DamusState) async throws {
        let event = try VoiceEventBuilder.restoredEvent(draft)
        let lifetime = state.voiceLifetime
        guard lifetime.isActive, state.pubkey.hex() == draft.context.account else { throw CancellationError() }
        try Task.checkCancellation()
        // Check durable ownership without overwriting acknowledgements received since this snapshot.
        try await store.requireSavedEvent(draft)
        try Task.checkCancellation()
        guard lifetime.isActive else { throw CancellationError() }
        await state.nostrNetwork.sendToNostrDB(event: event)
        guard lifetime.isActive else { throw CancellationError() }
        await state.nostrNetwork.postbox.sendVoice(event, isActive: { lifetime.isActive }) { [store] update in
            do { try await store.recordDelivery(update, for: draft) }
            catch {
                // The earlier queued manifest remains recoverable if a later status write fails.
                Log.error("Could not persist voice delivery status: %s", for: .networking, error.localizedDescription)
            }
        }
    }
}
