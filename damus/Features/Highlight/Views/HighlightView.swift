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

            // Show provenance - who is being highlighted
            if let event_ref = event.event_ref, let eventHex = hex_decode_id(event_ref) {
                EventLoaderView(damus_state: state, event_id: NoteId(eventHex)) { highlighted_event in
                    HighlightDescription(highlight_event: event, highlighted_event: highlighted_event, ndb: state.ndb)
                        .padding(.horizontal)
                        .padding(.bottom, 5)
                }
            } else if let addr_ref = event.addr_ref {
                // For addressable events, extract pubkey from "kind:pubkey:d-tag" format
                let components = addr_ref.split(separator: ":").map(String.init)
                if components.count >= 2, let pubkey = Pubkey(hex: components[1]) {
                    let profile_txn = state.profiles.lookup(id: pubkey, txn_name: "highlight-addr-desc")
                    let profile = profile_txn?.unsafeUnownedValue
                    let author_name = Profile.displayName(profile: profile, pubkey: pubkey).username.truncate(maxLength: 50)

                    HighlightAddressableDescription(author_name: author_name)
                        .padding(.horizontal)
                        .padding(.bottom, 5)
                }
            }

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
            } else if let addr_ref = event.addr_ref {
                HighlightAddressableEventRefInline(damus_state: state, addr_ref: addr_ref)
                    .padding(.horizontal)
                    .padding(.top, 5)
            } else if let evRef = event.event_ref {
                if let eventHex = hex_decode_id(evRef) {
                    HighlightEventRef(damus_state: state, event_ref: NoteId(eventHex))
                        .padding(.horizontal)
                        .padding(.top, 5)
                }
            }

        }
    }
}

// MARK: - Inline implementation for addressable event references

/// Inline view for addressable events (longform articles) in highlights
private struct HighlightAddressableEventRefInline: View {
    let damus_state: DamusState
    let addr_ref: String
    @State private var longformEvent: LongformEvent?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let longformEvent = longformEvent {
                NavigationLink(value: Route.Longform(event: longformEvent)) {
                    HStack(alignment: .top, spacing: 10) {
                        if let url = longformEvent.image {
                            KFAnimatedImage(url)
                                .callbackQueue(.dispatch(.global(qos:.background)))
                                .backgroundDecode(true)
                                .imageContext(.note, disable_animation: true)
                                .image_fade(duration: 0.25)
                                .cancelOnDisappear(true)
                                .configure { view in
                                    view.framePreloadCount = 3
                                }
                                .frame(width: 35, height: 35)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.gray.opacity(0.5), lineWidth: 0.5))
                                .scaledToFit()
                        } else {
                            Image("markdown")
                                .resizable()
                                .foregroundColor(DamusColors.neutral6)
                                .background(DamusColors.neutral3)
                                .frame(width: 35, height: 35)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).stroke(.gray.opacity(0.5), lineWidth: 0.5))
                        }

                        VStack(alignment: .leading, spacing: 5) {
                            Text(longformEvent.title ?? NSLocalizedString("Untitled", comment: "Title of longform event if it is untitled."))
                                .font(.system(size: 14, weight: .bold))
                                .lineLimit(1)
                                .foregroundColor(DamusColors.adaptableBlack)

                            let profile_txn = damus_state.profiles.lookup(id: longformEvent.event.pubkey, txn_name: "highlight-longform")
                            let profile = profile_txn?.unsafeUnownedValue

                            if let display_name = profile?.display_name {
                                Text(display_name)
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            } else if let name = profile?.name {
                                Text(name)
                                    .font(.system(size: 12))
                                    .foregroundColor(.gray)
                            }
                        }
                    }
                    .padding([.leading, .vertical], 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(DamusColors.adaptableWhite)
                    .cornerRadius(10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(DamusColors.neutral3, lineWidth: 2)
                    )
                }
                .buttonStyle(PlainButtonStyle())
            } else if isLoading {
                ProgressView()
                    .padding()
            } else {
                Text("Article not found", comment: "Message when highlighted article cannot be found")
                    .foregroundColor(.gray)
                    .font(.caption)
            }
        }
        .task {
            await loadLongformEvent()
        }
    }

    private func loadLongformEvent() async {
        // Parse addr_ref: "kind:pubkey:d-identifier"
        let components = addr_ref.split(separator: ":").map(String.init)
        guard components.count >= 3,
              let kind = UInt32(components[0]),
              let pubkey = Pubkey(hex: components[1]) else {
            isLoading = false
            return
        }

        let identifier = components[2]

        // Try NostrDB first
        if let txn = NdbTxn(ndb: damus_state.ndb) {
            let nostrFilter = NostrFilter(
                kinds: [NostrKind(rawValue: kind)].compactMap { $0 },
                authors: [pubkey]
            )

            guard let ndbFilter = try? NdbFilter(from: nostrFilter) else {
                isLoading = false
                return
            }

            let noteKeys = try? damus_state.ndb.query(with: txn, filters: [ndbFilter], maxResults: 100)
            if let noteKeys = noteKeys {
                for noteKey in noteKeys {
                    if let note = damus_state.ndb.lookup_note_by_key_with_txn(noteKey, txn: txn) {
                        // Check d-tag
                        var foundMatch = false
                        for i in 0..<Int(note.tags.count) {
                            let tag = note.tags[i]
                            if Int(tag.count) >= 2 {
                                let tag_name = tag[0].string()
                                let tag_value = tag[1].string()
                                if tag_name == "d" && tag_value == identifier {
                                    foundMatch = true
                                    break
                                }
                            }
                        }
                        if foundMatch {
                            self.longformEvent = LongformEvent.parse(from: note.to_owned())
                            self.isLoading = false
                            return
                        }
                    }
                }
            }
        }

        // Fetch from relays if not in DB
        await fetchFromRelays(kind: kind, pubkey: pubkey, identifier: identifier)
    }

    private func fetchFromRelays(kind: UInt32, pubkey: Pubkey, identifier: String) async {
        let filter = NostrFilter(
            kinds: [NostrKind(rawValue: kind)].compactMap { $0 },
            authors: [pubkey]
        )

        let sub_id = UUID().description

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var hasResumed = false

            damus_state.nostrNetwork.pool.subscribe_to(sub_id: sub_id, filters: [filter], to: nil) { relay_id, res in
                guard case .nostr_event(let ev_response) = res else { return }

                if case .event(_, let ev) = ev_response {
                    for tag in ev.tags {
                        if tag.count >= 2 && tag[0].string() == "d" && tag[1].string() == identifier {
                            self.longformEvent = LongformEvent.parse(from: ev)
                            self.isLoading = false
                            damus_state.nostrNetwork.pool.unsubscribe(sub_id: sub_id)
                            if !hasResumed {
                                continuation.resume()
                                hasResumed = true
                            }
                            return
                        }
                    }
                } else if case .eose = ev_response {
                    if !hasResumed {
                        self.isLoading = false
                        continuation.resume()
                        hasResumed = true
                    }
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                damus_state.nostrNetwork.pool.unsubscribe(sub_id: sub_id)
                if !hasResumed {
                    self.isLoading = false
                    continuation.resume()
                    hasResumed = true
                }
            }
        }
    }
}

struct HighlightView: View {
    let state: DamusState
    let event: HighlightEvent
    let options: EventViewOptions
    @State private var longformEvent: LongformEvent?

    init(state: DamusState, event: NostrEvent, options: EventViewOptions) {
        self.state = state
        self.event = HighlightEvent.parse(from: event)
        self.options = options.union(.no_mentions)
    }

    var body: some View {
        Group {
            if let longformEvent = longformEvent {
                NavigationLink(value: Route.Longform(event: longformEvent)) {
                    HighlightContent
                }
                .buttonStyle(PlainButtonStyle())
            } else {
                HighlightContent
            }
        }
        .task {
            // Load longform event if this highlight references an addressable event
            if let addr_ref = event.addr_ref {
                await loadLongformEvent(addr_ref: addr_ref)
            }
        }
    }

    private var HighlightContent: some View {
        VStack(alignment: .leading) {
            EventShell(state: state, event: event.event, options: options) {
                HighlightBodyView(state: state, ev: event, options: options)
            }
        }
    }

    private func loadLongformEvent(addr_ref: String) async {
        // Parse addr_ref: "kind:pubkey:d-identifier"
        let components = addr_ref.split(separator: ":").map(String.init)
        guard components.count >= 3,
              let kind = UInt32(components[0]),
              let pubkey = Pubkey(hex: components[1]) else {
            return
        }

        let identifier = components[2]

        // Try NostrDB first
        if let txn = NdbTxn(ndb: state.ndb) {
            let nostrFilter = NostrFilter(
                kinds: [NostrKind(rawValue: kind)].compactMap { $0 },
                authors: [pubkey]
            )

            guard let ndbFilter = try? NdbFilter(from: nostrFilter) else {
                return
            }

            let noteKeys = try? state.ndb.query(with: txn, filters: [ndbFilter], maxResults: 100)
            if let noteKeys = noteKeys {
                for noteKey in noteKeys {
                    if let note = state.ndb.lookup_note_by_key_with_txn(noteKey, txn: txn) {
                        // Check d-tag
                        for i in 0..<Int(note.tags.count) {
                            let tag = note.tags[i]
                            if Int(tag.count) >= 2 {
                                let tag_name = tag[0].string()
                                let tag_value = tag[1].string()
                                if tag_name == "d" && tag_value == identifier {
                                    self.longformEvent = LongformEvent.parse(from: note.to_owned())
                                    return
                                }
                            }
                        }
                    }
                }
            }
        }

        // Fetch from relays if not in DB
        await fetchFromRelays(kind: kind, pubkey: pubkey, identifier: identifier)
    }

    private func fetchFromRelays(kind: UInt32, pubkey: Pubkey, identifier: String) async {
        let filter = NostrFilter(
            kinds: [NostrKind(rawValue: kind)].compactMap { $0 },
            authors: [pubkey]
        )

        let sub_id = UUID().description

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            var hasResumed = false

            state.nostrNetwork.pool.subscribe_to(sub_id: sub_id, filters: [filter], to: nil) { relay_id, res in
                guard case .nostr_event(let ev_response) = res else { return }

                if case .event(_, let ev) = ev_response {
                    for tag in ev.tags {
                        if tag.count >= 2 && tag[0].string() == "d" && tag[1].string() == identifier {
                            self.longformEvent = LongformEvent.parse(from: ev)
                            state.nostrNetwork.pool.unsubscribe(sub_id: sub_id)
                            if !hasResumed {
                                continuation.resume()
                                hasResumed = true
                            }
                            return
                        }
                    }
                } else if case .eose = ev_response {
                    if !hasResumed {
                        continuation.resume()
                        hasResumed = true
                    }
                }
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                state.nostrNetwork.pool.unsubscribe(sub_id: sub_id)
                if !hasResumed {
                    continuation.resume()
                    hasResumed = true
                }
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
