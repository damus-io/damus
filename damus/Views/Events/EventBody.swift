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
    
    var content: String {
        event.get_content(damus_state.keypair.privkey)
    }
    
    var body: some View {
        if event_is_reply(event, privkey: damus_state.keypair.privkey) {
            ReplyDescription(event: event, profiles: damus_state.profiles)
        }

        let should_show_img = should_show_images(contacts: damus_state.contacts, ev: event, our_pubkey: damus_state.pubkey, booster_pubkey: nil)
        
        NoteContentView(privkey: damus_state.keypair.privkey, event: event, profiles: damus_state.profiles, previews: damus_state.previews, show_images: should_show_img, artifacts: .just_content(content), size: size)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct EventBody_Previews: PreviewProvider {
    static var previews: some View {
        EventBody(damus_state: test_damus_state(), event: test_event, size: .normal)
    }
}
