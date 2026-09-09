import Foundation

/// Keeps publication testable without real relays or real posts.
protocol VoicePublishing: Sendable {
    func publish(_ draft: VoiceDraft, state: DamusState) async throws
}

/// The open composer owns an exact signed event before handoff; PostBox owns delivery.
/// Closing its local composition does not retract an explicitly submitted post.
actor VoicePublisher: VoicePublishing {
    let store: VoiceDraftStore
    init(store: VoiceDraftStore = .shared) { self.store = store }

    func publish(_ draft: VoiceDraft, state: DamusState) async throws {
        let event = try VoiceEventBuilder.pendingEvent(draft)
        let lifetime = state.voiceLifetime
        guard lifetime.isActive, state.pubkey.hex() == draft.context.account else { throw CancellationError() }
        try Task.checkCancellation()
        // Check current ownership without overwriting newer acknowledgements.
        try await store.requireCurrentEvent(draft)
        try Task.checkCancellation()
        guard lifetime.isActive else { throw CancellationError() }
        await state.nostrNetwork.sendToNostrDB(event: event)
        guard lifetime.isActive else { throw CancellationError() }
        await state.nostrNetwork.postbox.sendVoice(event, isActive: { lifetime.isActive }) { [store] update in
            do { try await store.recordDelivery(update, for: draft) }
            catch {
                Log.error("Could not update voice delivery status: %s", for: .networking, error.localizedDescription)
            }
        }
    }
}
