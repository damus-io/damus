//
//  ReplyQuoteView.swift
//  damus
//
//  Created by William Casarin on 2022-04-19.
//

import SwiftUI

/// Displays a compact preview of the event being replied to.
///
/// Supports NIP-10 relay hints to fetch events from relays not in the user's pool.
struct ReplyQuoteView: View {
    let keypair: Keypair
    let quoter: NostrEvent
    let event_id: NoteId
    let state: DamusState
    @ObservedObject var thread: ThreadModel
    let options: EventViewOptions
    let relayHint: String?

    init(keypair: Keypair, quoter: NostrEvent, event_id: NoteId, state: DamusState, thread: ThreadModel, options: EventViewOptions, relayHint: String? = nil) {
        self.keypair = keypair
        self.quoter = quoter
        self.event_id = event_id
        self.state = state
        self.thread = thread
        self.options = options
        self.relayHint = relayHint
    }

    @State var can_show_event = true

    func update_should_show_event(event: NdbNote) async {
        self.can_show_event = await should_show_event(event: event, damus_state: state)
    }

    func content(event: NdbNote) -> some View {
        ZStack(alignment: .leading) {
            VStack(alignment: .leading) {
                HStack(alignment: .center) {
                    if can_show_event {
                        ProfilePicView(pubkey: event.pubkey, size: 14, highlight: .reply, profiles: state.profiles, disable_animation: false, damusState: state)
                        let blur_images = should_blur_images(settings: state.settings, contacts: state.contacts, ev: event, our_pubkey: state.pubkey)
                        NoteContentView(damus_state: state, event: event, blur_images: blur_images, size: .small, options: options)
                            .font(.callout)
                            .lineLimit(1)
                            .padding(.bottom, -7)
                            .padding(.top, -5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 20)
                            .clipped()
                    }
                    else {
                        Text("Note you've muted", comment: "Label indicating note has been muted")
                            .italic()
                            .font(.caption)
                            .opacity(0.5)
                            .padding(.bottom, -7)
                            .padding(.top, -5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(height: 20)
                            .clipped()
                    }
                }
            }
            .padding(5)
            .padding(.leading, 5+3)
            Rectangle()
                .foregroundStyle(.accent)
                .frame(width: 3)
        }
    }

    var body: some View {
        Group {
            if let event = state.events.lookup(event_id) {
                self.content(event: event)
                    .onAppear {
                        Task { await self.update_should_show_event(event: event) }
                    }
            } else if let relayHint, let relayURL = RelayURL(relayHint) {
                // Event not in cache - try to fetch using relay hint
                EventLoaderView(damus_state: state, event_id: event_id, relayHints: [relayURL]) { loaded_event in
                    self.content(event: loaded_event)
                        .onAppear {
                            Task { await self.update_should_show_event(event: loaded_event) }
                        }
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
