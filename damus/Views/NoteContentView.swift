//
//  NoteContentView.swift
//  damus
//
//  Created by William Casarin on 2022-05-04.
//

import SwiftUI
import LinkPresentation
import NaturalLanguage
import MarkdownUI

struct Blur: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemUltraThinMaterial

    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

struct NoteContentView: View {
    
    let damus_state: DamusState
    let event: NostrEvent
    @State var show_images: Bool
    let size: EventViewKind
    let preview_height: CGFloat?
    let options: EventViewOptions

    @ObservedObject var artifacts_model: NoteArtifactsModel
    @ObservedObject var preview_model: PreviewModel
    @ObservedObject var settings: UserSettingsStore

    var note_artifacts: NoteArtifacts {
        return self.artifacts_model.state.artifacts ?? .separated(.just_content(event.get_content(damus_state.keypair)))
    }
    
    init(damus_state: DamusState, event: NostrEvent, show_images: Bool, size: EventViewKind, options: EventViewOptions) {
        self.damus_state = damus_state
        self.event = event
        self.show_images = show_images
        self.size = size
        self.options = options
        self.preview_height = lookup_cached_preview_size(previews: damus_state.previews, evid: event.id)
        let cached = damus_state.events.get_cache_data(event.id)
        self._preview_model = ObservedObject(wrappedValue: cached.preview_model)
        self._artifacts_model = ObservedObject(wrappedValue: cached.artifacts_model)
        self._settings = ObservedObject(wrappedValue: damus_state.settings)
    }
    
    var truncate: Bool {
        return options.contains(.truncate_content)
    }
    
    var with_padding: Bool {
        return options.contains(.wide)
    }
    
    var preview: LinkViewRepresentable? {
        guard show_images,
              case .loaded(let preview) = preview_model.state,
              case .value(let cached) = preview else {
            return nil
        }
        
        return LinkViewRepresentable(meta: .linkmeta(cached))
    }
    
    func truncatedText(content: CompatibleText) -> some View {
        Group {
            if truncate {
                TruncatedText(text: content)
                    .font(eventviewsize_to_font(size, font_size: damus_state.settings.font_size))
            } else {
                content.text
                    .font(eventviewsize_to_font(size, font_size: damus_state.settings.font_size))
            }
        }
    }
    
    func invoicesView(invoices: [Invoice]) -> some View {
        InvoicesView(our_pubkey: damus_state.keypair.pubkey, invoices: invoices, settings: damus_state.settings)
    }

    var translateView: some View {
        TranslateView(damus_state: damus_state, event: event, size: self.size)
    }
    
    func previewView(links: [URL]) -> some View {
        Group {
            if let preview = self.preview, show_images {
                if let preview_height {
                    preview
                        .frame(height: preview_height)
                } else {
                    preview
                }
            } else if let link = links.first {
                LinkViewRepresentable(meta: .url(link))
                    .frame(height: 50)
            }
        }
    }
    
    func MainContent(artifacts: NoteArtifactsSeparated) -> some View {
        VStack(alignment: .leading) {
            if size == .selected {
                if with_padding {
                    SelectableText(attributedString: artifacts.content.attributed, size: self.size)
                        .padding(.horizontal)
                } else {
                    SelectableText(attributedString: artifacts.content.attributed, size: self.size)
                }
            } else {
                if with_padding {
                    truncatedText(content: artifacts.content)
                        .padding(.horizontal)
                } else {
                    truncatedText(content: artifacts.content)
                }
            }

            if !options.contains(.no_translate) && (size == .selected || damus_state.settings.auto_translate) {
                if with_padding {
                    translateView
                        .padding(.horizontal)
                } else {
                    translateView
                }
            }

            if show_images && artifacts.media.count > 0 {
                ImageCarousel(state: damus_state, evid: event.id, urls: artifacts.media)
            } else if !show_images && artifacts.media.count > 0 {
                ZStack {
                    ImageCarousel(state: damus_state, evid: event.id, urls: artifacts.media)
                    Blur()
                        .onTapGesture {
                            show_images = true
                        }
                }
                //.cornerRadius(10)
            }
            
            if artifacts.invoices.count > 0 {
                if with_padding {
                    invoicesView(invoices: artifacts.invoices)
                        .padding(.horizontal)
                } else {
                    invoicesView(invoices: artifacts.invoices)
                }
            }
            
            if with_padding {
                previewView(links: artifacts.links).padding(.horizontal)
            } else {
                previewView(links: artifacts.links)
            }
            
        }
    }
    
    func load(force_artifacts: Bool = false) {
        // always reload artifacts on load
        let plan = get_preload_plan(evcache: damus_state.events, ev: event, our_keypair: damus_state.keypair, settings: damus_state.settings)
        
        // TODO: make this cleaner
        Task {
            // this is surprisingly slow
            let rel = format_relative_time(event.created_at)
            Task { @MainActor in
                self.damus_state.events.get_cache_data(event.id).relative_time.value = rel
            }
            
            if var plan {
                if force_artifacts {
                    plan.load_artifacts = true
                }
                await preload_event(plan: plan, state: damus_state)
            } else if force_artifacts {
                let arts = render_note_content(ev: event, profiles: damus_state.profiles, keypair: damus_state.keypair)
                self.artifacts_model.state = .loaded(arts)
            }
        }
    }
    
    func artifactPartsView(_ parts: [ArtifactPart]) -> some View {
        
        LazyVStack(alignment: .leading) {
            ForEach(parts.indices, id: \.self) { ind in
                let part = parts[ind]
                switch part {
                case .text(let txt):
                    if with_padding {
                        txt.padding(.horizontal)
                    } else {
                        txt
                    }
                case .invoice(let inv):
                    if with_padding {
                        InvoiceView(our_pubkey: damus_state.pubkey, invoice: inv, settings: damus_state.settings)
                            .padding(.horizontal)
                    } else {
                        InvoiceView(our_pubkey: damus_state.pubkey, invoice: inv, settings: damus_state.settings)
                    }
                case .media(let media):
                    Text(verbatim: "media \(media.url.absoluteString)")
                }
            }
        }
    }
    
    var ArtifactContent: some View {
        Group {
            switch self.note_artifacts {
            case .longform(let md):
                Markdown(md.markdown)
                    .padding([.leading, .trailing, .top])
            case .separated(let separated):
                MainContent(artifacts: separated)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    var body: some View {
        ArtifactContent
            .onReceive(handle_notify(.profile_updated)) { profile in
                let blocks = event.blocks(damus_state.keypair)
                for block in blocks.blocks {
                    switch block {
                    case .mention(let m):
                        if case .pubkey(let pk) = m.ref, pk == profile.pubkey {
                            load(force_artifacts: true)
                            return
                        }
                    case .relay: return
                    case .text: return
                    case .hashtag: return
                    case .url: return
                    case .invoice: return
                    }
                }
            }
            .onAppear {
                load()
            }
    }
    
}

class NoteArtifactsParts {
    var parts: [ArtifactPart]
    var words: Int
    
    init(parts: [ArtifactPart], words: Int) {
        self.parts = parts
        self.words = words
    }
}

enum ArtifactPart {
    case text(Text)
    case media(MediaUrl)
    case invoice(Invoice)
    
    var is_text: Bool {
        switch self {
        case .text:    return true
        case .media:   return false
        case .invoice: return false
        }
    }
}

fileprivate func artifact_part_last_text_ind(parts: [ArtifactPart]) -> (Int, Text)? {
    let ind = parts.count - 1
    if ind < 0 {
        return nil
    }
    
    guard case .text(let txt) = parts[safe: ind] else {
        return nil
    }
    
    return (ind, txt)
}

func lookup_cached_preview_size(previews: PreviewCache, evid: NoteId) -> CGFloat? {
    guard case .value(let cached) = previews.lookup(evid) else {
        return nil
    }
    
    guard let height = cached.intrinsic_height else {
        return nil
    }
    
    return height
}

struct NoteContentView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state
        let state2 = test_damus_state

        Group {
            VStack {
                NoteContentView(damus_state: state, event: test_note, show_images: true, size: .normal, options: [])
            }
            .previewDisplayName("Short note")
            
            VStack {
                NoteContentView(damus_state: state, event: test_encoded_note_with_image!, show_images: true, size: .normal, options: [])
            }
            .previewDisplayName("Note with image")

            VStack {
                NoteContentView(damus_state: state2, event: test_longform_event.event, show_images: true, size: .normal, options: [.wide])
                    .border(Color.red)
            }
            .previewDisplayName("Long-form note")
        }
    }
}

func separate_images(ev: NostrEvent, keypair: Keypair) -> [MediaUrl]? {
    let urlBlocks: [URL] = ev.blocks(keypair).blocks.reduce(into: []) { urls, block in
        guard case .url(let url) = block else {
            return
        }
        if classify_url(url).is_img != nil {
            urls.append(url)
        }
    }
    let mediaUrls = urlBlocks.map { MediaUrl.image($0) }
    return mediaUrls.isEmpty ? nil : mediaUrls
}

