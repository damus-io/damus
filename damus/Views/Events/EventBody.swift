//
//  EventBody.swift
//  damus
//
//  Created by William Casarin on 2023-01-23.
//

import SwiftUI

struct EventBody: View {
    let damus_state: DamusState
    let event: NostrEvent
    let size: EventViewKind
    let should_show_img: Bool
    
    init(damus_state: DamusState, event: NostrEvent, size: EventViewKind, should_show_img: Bool? = nil) {
        self.damus_state = damus_state
        self.event = event
        self.size = size
        self.should_show_img = should_show_img ?? should_show_images(contacts: damus_state.contacts, ev: event, our_pubkey: damus_state.pubkey)
    }
    
    var content: String {
        event.get_content(damus_state.keypair.privkey)
    }
    
    var body: some View {
        if event_is_reply(event, privkey: damus_state.keypair.privkey) {
            ReplyDescription(event: event, profiles: damus_state.profiles)
        }

        NoteContentView(damus_state: damus_state, event: event, show_images: should_show_img, size: size, artifacts: .just_content(content), truncate: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EventBody_Previews: PreviewProvider {
    static var previews: some View {
        EventBody(damus_state: test_damus_state(), event: test_event, size: .normal)
    }
}
