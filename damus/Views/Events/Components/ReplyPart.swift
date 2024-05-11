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
                ReplyDescription(event: event, replying_to: events.lookup(reply_ref.note_id), ndb: ndb)
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
