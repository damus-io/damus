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
            VStack(alignment: .leading) {
                HStack(alignment: .top) {
                    ProfilePicView(pubkey: event.pubkey, size: 14, highlight: .reply, profiles: state.profiles, disable_animation: false)
                    let blur_images = should_blur_images(settings: state.settings, contacts: state.contacts, ev: event, our_pubkey: state.pubkey)
                    NoteContentView(damus_state: state, event: event, blur_images: blur_images, size: .small, options: options)
                        .font(.callout)
                        .lineLimit(1)
                    Spacer()
                }
            }
            .padding(5)
            .padding(.leading, 5+3)
            .background(Color.black.opacity(0.1))
            .overlay(content: {
                HStack {
                    Rectangle()
                        .foregroundStyle(.accent)
                        .frame(width: 3)
                    Spacer()
                }
            })
            .cornerRadius(5)
        }
    }

    var body: some View {
        Group {
            if let event = state.events.lookup(event_id) {
                VStack {
                    MainContent(event: event)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                }
            }
        }
    }
}

struct ReplyQuoteView_Previews: PreviewProvider {
    static var previews: some View {
        let s = test_damus_state
        let quoter = test_note
        ReplyQuoteView(keypair: s.keypair, quoter: quoter, event_id: test_note.id, state: s, thread: ThreadModel(event: quoter, damus_state: s), options: [.no_previews, .no_action_bar, .truncate_content_very_short, .no_show_more, .no_translate])
    }
}
