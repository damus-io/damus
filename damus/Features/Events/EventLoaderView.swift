//
//  EventLoaderView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-09-27.
//

import SwiftUI

/// This view handles the loading logic for Nostr events, so that you can easily use views that require `NostrEvent`, even if you only have a `NoteId`.
///
/// Supports NIP-01/NIP-10 relay hints to fetch events from relays not in the user's pool.
struct EventLoaderView<Content: View>: View {
    let damus_state: DamusState
    let event_id: NoteId
    let relayHints: [RelayURL]
    @State var event: NostrEvent?
    @State var subscription_uuid: String = UUID().description
    @State var loadingTask: Task<Void, Never>? = nil
    let content: (NostrEvent) -> Content

    /// Creates an event loader view.
    ///
    /// - Parameters:
    ///   - damus_state: The app's shared state.
    ///   - event_id: The ID of the event to load.
    ///   - relayHints: Optional relay URLs where the event may be found (per NIP-01/NIP-10).
    ///   - content: A view builder that receives the loaded event.
    init(damus_state: DamusState, event_id: NoteId, relayHints: [RelayURL] = [], @ViewBuilder content: @escaping (NostrEvent) -> Content) {
        self.damus_state = damus_state
        self.event_id = event_id
        self.relayHints = relayHints
        self.content = content
        let event = damus_state.events.lookup(event_id)
        _event = State(initialValue: event)
    }
    
    func unsubscribe() {
        self.loadingTask?.cancel()
    }
    
    /// Attempts to load the event with retry logic for transient failures.
    ///
    /// Retries up to 3 times with exponential backoff (0.5s, 1.0s, 2.0s) when the event
    /// is not found, handling cases where events arrive late from relays.
    /// Runs off the main actor to avoid blocking SwiftUI.
    func subscribe() {
        self.loadingTask?.cancel()
        let eventState = _event  // Capture @State wrapper for detached task access
        self.loadingTask = Task.detached(priority: .userInitiated) { [damus_state, event_id, relayHints, eventState] in
            let targetRelays = relayHints.isEmpty ? nil : relayHints

            for attempt in 1...3 {
                guard !Task.isCancelled else { return }

                let lender = try? await damus_state.nostrNetwork.reader.lookup(noteId: event_id, to: targetRelays)

                var copiedEvent: NostrEvent?
                lender?.justUseACopy({ copiedEvent = $0 })

                if let copiedEvent {
                    await MainActor.run {
                        eventState.wrappedValue = copiedEvent
                    }
                    return
                }

                // Event not found - retry with exponential backoff
                guard attempt < 3 else { break }
                try? await Task.sleep(for: .seconds(0.5 * pow(2.0, Double(attempt - 1))))
            }
        }
    }
    
    func load() {
        subscribe()
    }
    
    var body: some View {
        VStack {
            if let event {
                self.content(event)
            } else {
                ProgressView().padding()
            }
        }
        .onAppear {
            guard event == nil else {
                return
            }
            self.load()
        }
    }
}


struct EventLoaderView_Previews: PreviewProvider {
    static var previews: some View {
        EventLoaderView(damus_state: test_damus_state, event_id: test_note.id) { event in
            EventView(damus: test_damus_state, event: event)
        }
    }
}
