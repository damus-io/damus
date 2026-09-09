import SwiftUI

/// Recovery is reachable from any public composer, including after an app restart.
struct VoiceDraftLibrary: View {
    let state: DamusState
    @Environment(\.dismiss) private var dismiss
    @State private var inventory: VoiceDraftStore.Inventory?
    @State private var error: String?

    var body: some View {
        NavigationStack {
            List {
                if let inventory {
                    if inventory.drafts.isEmpty { Text("No saved voice recordings for this account.") }
                    ForEach(inventory.drafts) { draft in
                        Button { notify(.present_sheet(.voice_draft(draft))) } label: {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(title(draft)).font(.headline)
                                Text(draft.transcript.map { String($0.prefix(300)) } ?? "Recording awaiting transcription")
                                    .font(.subheadline).lineLimit(3)
                                Text(status(draft)).font(.caption).foregroundColor(.secondary)
                                Text(draft.updatedAt, style: .relative).font(.caption).foregroundColor(.secondary)
                            }
                        }
                        .accessibilityIdentifier("voice.saved." + draft.id.uuidString)
                    }
                    if inventory.unreadableCount > 0 {
                        Text("Some saved recordings could not be read. Their files have been preserved.")
                            .foregroundColor(.secondary)
                    }
                } else if error == nil { ProgressView("Loading saved recordings…") }
                if let error { Text(error).foregroundColor(.red) }
            }
            .navigationTitle("Saved audio")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
            .task {
                do {
                    let result = try await VoiceDraftStore.shared.inventory(account: state.pubkey.hex())
                    try Task.checkCancellation()
                    inventory = result
                } catch is CancellationError {}
                catch { self.error = error.localizedDescription }
            }
        }
    }

    private func title(_ draft: VoiceDraft) -> String {
        switch draft.context.kind {
        case .post: return "Voice post"
        case .reply: return "Voice reply"
        case .quote: return "Voice quote"
        }
    }

    private func status(_ draft: VoiceDraft) -> String {
        switch draft.phase {
        case .draft: return draft.pendingTakeID == nil ? "Draft" : "Interrupted recording"
        case .queued, .dispatched: return "Waiting for relay acceptance"
        case .accepted: return "Accepted by a relay"
        case .rejected, .retryable: return "Saved for retry"
        }
    }
}

/// Resolve the saved signed parent off the main actor before reopening its original composer.
struct VoiceDraftRestoreView: View {
    let state: DamusState
    let draft: VoiceDraft
    @State private var action: PostAction?
    @State private var error: String?

    var body: some View {
        Group {
            if let action {
                PostView(action: action, damus_state: state, restoring_voice: true)
            } else {
                VStack(spacing: 16) {
                    if let error { Text(error).foregroundColor(.red) }
                    else { ProgressView("Restoring voice draft…") }
                    Button("Saved audio") { notify(.present_sheet(.voice_drafts)) }
                }
                .padding()
            }
        }
        .task(id: draft.id) {
            do {
                guard draft.context.account == state.pubkey.hex(), state.voiceLifetime.isActive else { throw CancellationError() }
                let saved = draft
                let restored = try await Task.detached { () throws -> PostAction in
                    let target = try saved.context.target()
                    switch saved.context.kind {
                    case .post:
                        if let recipient = saved.context.recipient, let pubkey = Pubkey(hex: recipient) { return .posting(.user(pubkey)) }
                        return .posting(.none)
                    case .reply:
                        guard let target else { throw VoiceFailure("The original reply target is missing.") }
                        return .replying_to(target)
                    case .quote:
                        guard let target else { throw VoiceFailure("The original quote target is missing.") }
                        return .quoting(target)
                    }
                }.value
                try Task.checkCancellation()
                guard state.voiceLifetime.isActive else { throw CancellationError() }
                action = restored
            } catch is CancellationError {}
            catch { self.error = error.localizedDescription }
        }
    }
}
