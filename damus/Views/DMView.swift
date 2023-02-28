//
//  DMView.swift
//  damus
//
//  Created by William Casarin on 2022-07-01.
//

import SwiftUI

struct DMView: View {
    let event: NostrEvent
    let damus_state: DamusState

    var is_ours: Bool {
        event.pubkey == damus_state.pubkey
    }

    var body: some View {
        HStack {
            if is_ours {
                Spacer(minLength: UIScreen.main.bounds.width * 0.2)
            }

            let should_show_img = should_show_images(contacts: damus_state.contacts, ev: event, our_pubkey: damus_state.pubkey)

            NoteContentView(damus_state: damus_state, event: event, show_images: should_show_img, size: .normal, artifacts: .just_content(event.get_content(damus_state.keypair.privkey)))
                .foregroundColor(is_ours ? Color.white : Color.primary)
                .padding(10)
                .background(is_ours ? Color.accentColor : Color.secondary.opacity(0.15))
                .cornerRadius(8.0)
                .tint(is_ours ? Color.white : Color.accentColor)
            if !is_ours {
                Spacer(minLength: UIScreen.main.bounds.width * 0.2)
            }
        }
    }
}

struct DMView_Previews: PreviewProvider {
    static var previews: some View {
        let ev = NostrEvent(content: "Hey there *buddy*, want to grab some drinks later? 🍻", pubkey: "pubkey", kind: 1, tags: [])
        DMView(event: ev, damus_state: test_damus_state())
    }
}
