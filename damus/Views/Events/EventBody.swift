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
    let options: EventViewOptions
    
    init(damus_state: DamusState, event: NostrEvent, size: EventViewKind, should_show_img: Bool? = nil, options: EventViewOptions) {
        self.damus_state = damus_state
        self.event = event
        self.size = size
        self.options = options
        self.should_show_img = should_show_img ?? should_show_images(settings: damus_state.settings, contacts: damus_state.contacts, ev: event, our_pubkey: damus_state.pubkey)
    }
    
    var content: String {
        event.get_content(damus_state.keypair.privkey)
    }
    
    var body: some View {
        NoteContentView(damus_state: damus_state, event: event, show_images: should_show_img, size: size, artifacts: .just_content(content), options: options)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EventBody_Previews: PreviewProvider {
    static var previews: some View {
        EventBody(damus_state: test_damus_state(), event: test_event, size: .normal, options: [])
    }
}
