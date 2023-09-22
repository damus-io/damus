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

    var replying_to: NostrEvent? {
        guard let note_ref = event.event_refs(keypair).first(where: { evref in evref.is_direct_reply != nil })?.is_direct_reply else {
            return nil
        }

        return events.lookup(note_ref.note_id)
    }

    var body: some View {
        Group {
            if event_is_reply(event.event_refs(keypair)) {
                ReplyDescription(event: event, replying_to: replying_to, ndb: ndb)
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
