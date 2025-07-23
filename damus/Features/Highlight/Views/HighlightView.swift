//
//  HighlightView.swift
//  damus
//
//  Created by eric on 4/22/24.
//

import SwiftUI
import Kingfisher

struct HighlightTruncatedText: View {
    let attributedString: AttributedString
    let maxChars: Int

    init(attributedString: AttributedString, maxChars: Int = 360) {
        self.attributedString = attributedString
        self.maxChars = maxChars
    }

    var body: some View {
        VStack(alignment: .leading) {

            let truncatedAttributedString: AttributedString? = attributedString.truncateOrNil(maxLength: maxChars)

            if let truncatedAttributedString {
                Text(truncatedAttributedString)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(attributedString)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if truncatedAttributedString != nil {
                Spacer()
                Button(NSLocalizedString("Show more", comment: "Button to show entire note.")) { }
                    .allowsHitTesting(false)
            }
        }
    }
}

struct HighlightBodyView: View {
    let state: DamusState
    let event: HighlightEvent
    let options: EventViewOptions

    init(state: DamusState, ev: HighlightEvent, options: EventViewOptions) {
        self.state = state
        self.event = ev
        self.options = options
    }

    init(state: DamusState, ev: NostrEvent, options: EventViewOptions) {
        self.state = state
        self.event = HighlightEvent.parse(from: ev)
        self.options = options
    }

    var body: some View {
        Group {
            if options.contains(.wide) {
                Main
            } else {
                Main.padding(.horizontal)
            }
        }
    }

    var truncate: Bool {
        return options.contains(.truncate_content)
    }

    var truncate_very_short: Bool {
        return options.contains(.truncate_content_very_short)
    }

    func truncatedText(attributedString: AttributedString) -> some View {
        Group {
            if truncate_very_short {
                HighlightTruncatedText(attributedString: attributedString, maxChars: 140)
                    .font(eventviewsize_to_font(.normal, font_size: state.settings.font_size))
            }
            else if truncate {
                HighlightTruncatedText(attributedString: attributedString)
                    .font(eventviewsize_to_font(.normal, font_size: state.settings.font_size))
            } else {
                Text(attributedString)
                    .font(eventviewsize_to_font(.normal, font_size: state.settings.font_size))
            }
        }
    }

    var Main: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            if self.event.event.referenced_comment_items.first?.content != nil {
                let all_options = options.union(.no_action_bar)
                NoteContentView(
                    damus_state: self.state,
                    event: self.event.event,
                    blur_images: should_blur_images(damus_state: self.state, ev: self.event.event),
                    size: .normal,
                    options: all_options
                ).padding(.vertical, 10)
            }
            
            HStack {
                var attributedString: AttributedString {
                    var attributedString: AttributedString = ""
                    if let context = event.context {
                        if context.count < event.event.content.count {
                            attributedString = AttributedString(event.event.content)
                        } else {
                            attributedString = AttributedString(context)
                        }
                    } else {
                        attributedString = AttributedString(event.event.content)
                    }

                    if let range = attributedString.range(of: event.event.content) {
                        attributedString[range].backgroundColor = DamusColors.highlight
                    }
                    return attributedString
                }

                truncatedText(attributedString: attributedString)
                    .lineSpacing(5)
                    .padding(10)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 25).fill(DamusColors.highlight).frame(width: 4),
                alignment: .leading
            )
            .padding(.horizontal)
            .padding(.bottom, 10)

            if let url = event.url_ref {
                HighlightLink(state: state, url: url, content: event.event.content)
                    .padding(.horizontal)
            } else {
                if let evRef = event.event_ref {
                    if let eventHex = hex_decode_id(evRef) {
                        HighlightEventRef(damus_state: state, event_ref: NoteId(eventHex))
                            .padding(.horizontal)
                            .padding(.top, 5)
                    }
                }
            }

        }
    }
}

struct HighlightView: View {
    let state: DamusState
    let event: HighlightEvent
    let options: EventViewOptions

    init(state: DamusState, event: NostrEvent, options: EventViewOptions) {
        self.state = state
        self.event = HighlightEvent.parse(from: event)
        self.options = options.union(.no_mentions)
    }

    var body: some View {
        VStack(alignment: .leading) {
            EventShell(state: state, event: event.event, options: options) {
                HighlightBodyView(state: state, ev: event, options: options)
            }
        }
    }
}

struct HighlightView_Previews: PreviewProvider {
    static var previews: some View {

        let content = "Nostr, a decentralized and open social network protocol. Without ads, toxic algorithms, or censorship"
        let context = "Damus is built on Nostr, a decentralized and open social network protocol. Without ads, toxic algorithms, or censorship, Damus gives you access to the social network that a truly free and healthy society needs — and deserves."

        let test_highlight_event = HighlightEvent.parse(from: NostrEvent(
            content: content,
            keypair: test_keypair,
            kind: NostrKind.highlight.rawValue,
            tags: [
                ["context", context],
                ["r", "https://damus.io"],
                ["p", "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"],
            ])!
        )

        let test_highlight_event2 = HighlightEvent.parse(from: NostrEvent(
            content: content,
            keypair: test_keypair,
            kind: NostrKind.highlight.rawValue,
            tags: [
                ["context", context],
                ["e", "36017b098859d62e1dbd802290d59c9de9f18bb0ca00ba4b875c2930dd5891ae"],
                ["p", "32e1827635450ebb3c5a7d12c1f8e7b2b514439ac10a67eef3d9fd9c5c68e245"],
            ])!
        )
        VStack {
            HighlightView(state: test_damus_state, event: test_highlight_event.event, options: [])

            HighlightView(state: test_damus_state, event: test_highlight_event2.event, options: [.wide])
        }
    }
}
