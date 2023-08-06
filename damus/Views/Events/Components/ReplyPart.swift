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
    let privkey: Privkey?
    let profiles: Profiles

    var replying_to: NostrEvent? {
        guard let note_ref = event.event_refs(privkey).first(where: { evref in evref.is_direct_reply != nil })?.is_direct_reply else {
            return nil
        }

        return events.lookup(note_ref.note_id)
    }

    var body: some View {
        Group {
            if event_is_reply(event.event_refs(privkey)) {
                ReplyDescription(event: event, replying_to: replying_to, profiles: profiles)
            } else {
                EmptyView()
            }
        }
    }
}

struct ReplyPart_Previews: PreviewProvider {
    static var previews: some View {
        ReplyPart(events: test_damus_state().events, event: test_note, privkey: nil, profiles: test_damus_state().profiles)
    }
}
