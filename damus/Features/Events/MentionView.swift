//
//  MentionView.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-09-27.
//

import SwiftUI

/// A view that renders an inline mention of a Nostr event.
///
/// Supports NIP-01/NIP-10 relay hints to fetch events from relays not in the user's pool.
struct MentionView: View {
    let damus_state: DamusState
    let mention: Mention<NoteId>
    let relayHints: [RelayURL]

    /// Creates a mention view.
    ///
    /// - Parameters:
    ///   - damus_state: The app's shared state.
    ///   - mention: The mention containing the note ID.
    ///   - relayHints: Optional relay URLs where the event may be found (per NIP-01/NIP-10).
    init(damus_state: DamusState, mention: Mention<NoteId>, relayHints: [RelayURL] = []) {
        self.damus_state = damus_state
        self.mention = mention
        self.relayHints = relayHints
    }

    var body: some View {
        EventLoaderView(damus_state: damus_state, event_id: mention.ref, relayHints: relayHints) { event in
            EventMutingContainerView(damus_state: damus_state, event: event) {
                BuilderEventView(damus: damus_state, event_id: mention.ref, relayHints: relayHints)
            }
        }
    }
}

struct MentionView_Previews: PreviewProvider {
    static var previews: some View {
        MentionView(damus_state: test_damus_state, mention: .note(test_note.id))
    }
}
