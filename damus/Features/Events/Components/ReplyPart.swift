//
//  ReplyPart.swift
//  damus
//
//  Created by William Casarin on 2023-06-01.
//

import SwiftUI

/// The slot under a note's author for the one line saying what the note stands in relation to: what
/// it highlights, or who it replies to.
struct ReplyPart: View {
    let state: DamusState
    let event: NostrEvent

    var body: some View {
        Group {
            if event.known_kind == .highlight {
                let highlighted_note = event.highlighted_note_id().flatMap { state.events.lookup($0) }
                let highlight_note = HighlightEvent.parse(from: event)
                HighlightDescription(highlight_event: highlight_note, highlighted_event: highlighted_note, ndb: state.ndb)
            } else if let reply_ref = event.thread_reply()?.reply {
                let replying_to = state.events.lookup(reply_ref.note_id)
                ReplyDescription(state: state, event: event, replying_to: replying_to)
            } else if event.is_private_reply {
                // A gift-wrapped kind 1 that does not parse as a reply — one we did not write, from a
                // client that wrapped a note rather than a reply — still has to say it is private, and
                // this line is where every other surface says it. Without this branch it would be the
                // one private note in the app that renders exactly like a public one.
                ReplyDescription(state: state, event: event, replying_to: nil)
            }
        }
    }
}

struct ReplyPart_Previews: PreviewProvider {
    static var previews: some View {
        ReplyPart(state: test_damus_state, event: test_note)
    }
}
