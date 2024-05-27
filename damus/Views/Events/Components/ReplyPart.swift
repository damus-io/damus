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
            if let reply_ref = event.thread_reply()?.reply {
                let replying_to = events.lookup(reply_ref.note_id)
                if event.known_kind != .highlight {
                    ReplyDescription(event: event, replying_to: replying_to, ndb: ndb)
                } else if event.known_kind == .highlight {
                    HighlightDescription(event: event, highlighted_event: replying_to, ndb: ndb)
                }
                else {
                    EmptyView()
                }
            } else {
                EmptyView()
            }
        }
    }
}

struct ReplyPart_Previews: PreviewProvider {
    static var previews: some View {
        ReplyPart(events: test_damus_state.events, event: test_note, keypair: Keypair(pubkey: .empty, privkey: nil), ndb: test_damus_state.ndb)
    }
}
