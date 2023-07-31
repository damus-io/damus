//
//  ReplyPart.swift
//  damus
//
//  Created by William Casarin on 2023-06-01.
//

import SwiftUI

struct ReplyPart: View {
    let event: NostrEvent
    let privkey: Privkey?
    let profiles: Profiles
    
    var body: some View {
        Group {
            if event_is_reply(event.event_refs(privkey)) {
                ReplyDescription(event: event, profiles: profiles)
            } else {
                EmptyView()
            }
        }
    }
}

struct ReplyPart_Previews: PreviewProvider {
    static var previews: some View {
        ReplyPart(event: test_note, privkey: nil, profiles: test_damus_state().profiles)
    }
}
