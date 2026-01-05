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
    
    func subscribe() {
        self.loadingTask?.cancel()
        self.loadingTask = Task {
            let targetRelays = relayHints.isEmpty ? nil : relayHints
            let lender = try? await damus_state.nostrNetwork.reader.lookup(noteId: self.event_id, to: targetRelays)
            lender?.justUseACopy({ event = $0 })
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
