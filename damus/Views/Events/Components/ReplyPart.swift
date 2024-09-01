//
//  ReplyPart.swift
//  damus
//
//  Created by William Casarin on 2023-06-01.
//

import SwiftUI

struct ReplyPart: View {
    let events: EventCache
    let event: NostrEvent
    let keypair: Keypair
    let ndb: Ndb

    var body: some View {
        Group {
            if event.known_kind == .highlight {
                let highlighted_note = event.highlighted_note_id().flatMap { events.lookup($0) }
                let highlight_note = HighlightEvent.parse(from: event)
                HighlightDescription(highlight_event: highlight_note, highlighted_event: highlighted_note, ndb: ndb)
            } else if let reply_ref = event.thread_reply()?.reply {
                let replying_to = events.lookup(reply_ref.note_id)
                ReplyDescription(event: event, replying_to: replying_to, ndb: ndb)
            }
        }
    }
}

struct ReplyPart_Previews: PreviewProvider {
    static var previews: some View {
        ReplyPart(events: test_damus_state.events, event: test_note, keypair: Keypair(pubkey: .empty, privkey: nil), ndb: test_damus_state.ndb)
    }
}
