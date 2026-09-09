import SwiftUI

/// Verify both signed events off the UI thread before attributing a voice repost.
struct VoiceRepostedEvent: View {
    let damus: DamusState
    let event: NostrEvent
    let options: EventViewOptions
    @State private var original: NostrEvent?
    @State private var loading = true

    var body: some View {
        Group {
            if let original {
                RepostedEvent(damus: damus, event: event, inner_ev: original, options: options)
            } else if loading {
                ProgressView()
                    .accessibilityLabel("Verifying voice repost")
            } else {
                Text("This voice repost could not be verified.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .task(id: event.id) {
            loading = true
            original = nil
            let owned = event.to_owned()
            let work = Task.detached(priority: .userInitiated) {
                guard !Task.isCancelled else { return nil as NostrEvent? }
                return owned.get_inner_event()
            }
            let verified = await withTaskCancellationHandler {
                await work.value
            } onCancel: {
                work.cancel()
            }
            guard !Task.isCancelled else { return }
            original = verified
            loading = false
        }
    }
}
