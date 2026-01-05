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
    let should_blur_img: Bool
    let options: EventViewOptions

    @Environment(\.colorScheme) var colorScheme

    init(damus_state: DamusState, event: NostrEvent, size: EventViewKind, should_blur_img: Bool? = nil, options: EventViewOptions) {
        self.damus_state = damus_state
        self.event = event
        self.size = size
        self.options = options
        self.should_blur_img = should_blur_img ?? should_blur_images(settings: damus_state.settings, contacts: damus_state.contacts, ev: event, our_pubkey: damus_state.pubkey)
    }

    var note_content: some View {
        NoteContentView(damus_state: damus_state, event: event, blur_images: should_blur_img, size: size, options: options)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    var body: some View {
        if event.known_kind == .longform {
            let isFullArticle = !options.contains(.truncate_content)
            let sepiaEnabled = damus_state.settings.longform_sepia_mode

            if isFullArticle && sepiaEnabled {
                // Wrap in single sepia container to eliminate gaps
                VStack(spacing: 0) {
                    LongformPreviewBody(
                        state: damus_state,
                        ev: event,
                        options: options,
                        header: true,
                        sepiaEnabled: true
                    )
                    note_content
                }
                .background(DamusColors.sepiaBackground(for: colorScheme))
            } else {
                LongformPreviewBody(
                    state: damus_state,
                    ev: event,
                    options: options,
                    header: true,
                    sepiaEnabled: false
                )

                // truncated longform bodies are just the preview
                if isFullArticle {
                    note_content
                }
            }
        } else if event.known_kind == .highlight {
            HighlightBodyView(state: damus_state, ev: event, options: options)
                .onTapGesture {
                    if let highlighted_note = event.highlighted_note_id().flatMap({ damus_state.events.lookup($0) }) {
                        let thread = ThreadModel(event: highlighted_note, damus_state: damus_state)
                        damus_state.nav.push(route: Route.Thread(thread: thread))
                    }
                }
        } else {
            note_content
        }
    }
}

struct EventBody_Previews: PreviewProvider {
    static var previews: some View {
        EventBody(damus_state: test_damus_state, event: test_note, size: .normal, options: [])
    }
}
