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
    
    var Mention: some View {
        Group {
            if let mention = first_eref_mention(ndb: damus_state.ndb, ev: event, keypair: damus_state.keypair) {
                BuilderEventView(damus: damus_state, event_id: mention.ref)
            } else {
                EmptyView()
            }
        }
    }
    
    var dm_options: EventViewOptions {
        /*
        if self.damus_state.settings.translate_dms {
            return []
        }
         */

        return [.no_translate]
    }
    
    var DM: some View {
        HStack {
            if is_ours {
                Spacer(minLength: UIScreen.main.bounds.width * 0.2)
            }

            let should_blur_img = should_blur_images(settings: damus_state.settings, contacts: damus_state.contacts, ev: event, our_pubkey: damus_state.pubkey)

            VStack(alignment: .trailing) {
                NoteContentView(damus_state: damus_state, event: event, blur_images: should_blur_img, size: .normal, options: dm_options)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding([.top, .leading, .trailing], 10)
                    .padding([.bottom], 10)
                    .background(VisualEffectView(effect: UIBlurEffect(style: .prominent))
                        .background(is_ours ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.15))
                    )
                    .cornerRadius(8.0)
                    .tint(is_ours ? Color.white : Color.accentColor)

                Text(format_relative_time(event.created_at))
                   .font(.footnote)
                   .foregroundColor(.gray)
                   .opacity(0.8)
            }

            if !is_ours {
                Spacer(minLength: UIScreen.main.bounds.width * 0.2)
            }
        }
    }
    
    var body: some View {
        VStack {
            Mention
            DM
        }
        
    }
}

struct DMView_Previews: PreviewProvider {
    static var previews: some View {
        let ev = NostrEvent(content: "Hey there *buddy*, want to grab some drinks later? 🍻", keypair: test_keypair, kind: 1, tags: [])!
        DMView(event: ev, damus_state: test_damus_state)
    }
}
