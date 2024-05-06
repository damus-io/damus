//
//  SwiftUIView.swift
//  damus
//
//  Created by William Casarin on 2022-04-19.
//

import SwiftUI

struct ReplyQuoteView: View {
    let keypair: Keypair
    let quoter: NostrEvent
    let event_id: NoteId
    let state: DamusState
    @ObservedObject var thread: ThreadModel
    let options: EventViewOptions

    func MainContent(event: NostrEvent) -> some View {
        HStack(alignment: .top) {
            Rectangle()
                .frame(width: 2)
                .padding([.leading], 4)
                .foregroundColor(.accentColor)
            
            VStack(alignment: .leading) {
                HStack(alignment: .top) {
                    ProfilePicView(pubkey: event.pubkey, size: 16, highlight: .reply, profiles: state.profiles, disable_animation: false)
                    ProfileName(pubkey: event.pubkey, damus: state)
                        .foregroundColor(.accentColor)
                    RelativeTime(time: state.events.get_cache_data(event.id).relative_time)
                }
                
                let blur_images = should_blur_images(settings: state.settings, contacts: state.contacts, ev: event, our_pubkey: state.pubkey)
                NoteContentView(damus_state: state, event: event, blur_images: blur_images, size: .normal, options: options)
                    .font(.callout)
                    .foregroundColor(.accentColor)

                //Spacer()
            }
            //.border(Color.red)
        }
        //.border(Color.green)
    }
    
    var body: some View {
        Group {
            if let event = state.events.lookup(event_id) {
                VStack {
                    MainContent(event: event)
                        .padding(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())

                    ReplyDescription(event: event, replying_to: event, ndb: state.ndb)
                }
            }
        }
    }
}

struct ReplyQuoteView_Previews: PreviewProvider {
    static var previews: some View {
        let s = test_damus_state
        let quoter = test_note
        ReplyQuoteView(keypair: s.keypair, quoter: quoter, event_id: test_note.id, state: s, thread: ThreadModel(event: quoter, damus_state: s), options: [.no_media, .truncate_content])
    }
}
