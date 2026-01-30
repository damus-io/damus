//
//  BuilderEventView.swift
//  damus
//
//  Created by William Casarin on 2023-01-23.
//

import SwiftUI

/// A view that displays an embedded/quoted Nostr event.
///
/// Supports NIP-01/NIP-10 relay hints to fetch events from relays not in the user's pool.
struct BuilderEventView: View {
    let damus: DamusState
    let event_id: NoteId
    let event: NostrEvent?
    let relayHints: [RelayURL]

    /// Creates a builder event view with a pre-loaded event.
    init(damus: DamusState, event: NostrEvent) {
        self.event = event
        self.damus = damus
        self.event_id = event.id
        self.relayHints = []
    }

    /// Creates a builder event view that will load the event by ID.
    ///
    /// - Parameters:
    ///   - damus: The app's shared state.
    ///   - event_id: The ID of the event to load.
    ///   - relayHints: Optional relay URLs where the event may be found (per NIP-01/NIP-10).
    init(damus: DamusState, event_id: NoteId, relayHints: [RelayURL] = []) {
        self.event_id = event_id
        self.damus = damus
        self.event = nil
        self.relayHints = relayHints
    }
    
    func Event(event: NostrEvent) -> some View {
        return EventView(damus: damus, event: event, options: .embedded)
            .padding([.top, .bottom], 8)
            .onTapGesture {
                let ev = event.get_inner_event(cache: damus.events) ?? event
                let thread = ThreadModel(event: ev, damus_state: damus)
                damus.nav.push(route: .Thread(thread: thread))
            }
    }
    
    var body: some View {
        VStack {
            if let event {
                self.Event(event: event)
            } else {
                EventLoaderView(damus_state: damus, event_id: self.event_id, relayHints: relayHints) { loaded_event in
                    self.Event(event: loaded_event)
                }
            }
        }
        .frame(minWidth: 0, maxWidth: .infinity)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1.0)
        )
    }
}

struct BuilderEventView_Previews: PreviewProvider {
    static var previews: some View {
        BuilderEventView(damus: test_damus_state, event_id: test_note.id)
    }
}

