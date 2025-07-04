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
import Translation

struct Blur: UIViewRepresentable {
    var style: UIBlurEffect.Style = .systemUltraThinMaterial

    func makeUIView(context: Context) -> UIVisualEffectView {
        return UIVisualEffectView(effect: UIBlurEffect(style: style))
    }

    func updateUIView(_ uiView: UIVisualEffectView, context: Context) {
        uiView.effect = UIBlurEffect(style: style)
    }
}

extension bech32_nprofile {
    func matches_pubkey(pk: Pubkey) -> Bool {
        pk.id.withUnsafeBytes { bytes in
            memcmp(self.pubkey, bytes, 32) == 0
        }
    }
}

extension bech32_npub {
    func matches_pubkey(pk: Pubkey) -> Bool {
        pk.id.withUnsafeBytes { bytes in
            memcmp(self.pubkey, bytes, 32) == 0
        }
    }
}

struct NoteContentView: View {
    
    let damus_state: DamusState
    let event: NostrEvent
    @State var blur_images: Bool
    @State var load_media: Bool = false
    let size: EventViewKind
    let preview_height: CGFloat?
    let options: EventViewOptions

    @State var isAppleTranslationPopoverPresented: Bool = false

    @ObservedObject var artifacts_model: NoteArtifactsModel
    @ObservedObject var preview_model: PreviewModel
    @ObservedObject var settings: UserSettingsStore

    var note_artifacts: NoteArtifacts {
        if damus_state.settings.undistractMode {
            return .separated(.just_content(Undistractor.makeGibberish(text: event.get_content(damus_state.keypair))))
        }
        return self.artifacts_model.state.artifacts ?? .separated(.just_content(event.get_content(damus_state.keypair)))
    }
    
    init(damus_state: DamusState, event: NostrEvent, blur_images: Bool, size: EventViewKind, options: EventViewOptions) {
        self.damus_state = damus_state
        self.event = event
        self.blur_images = blur_images
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
    
    var truncate_very_short: Bool {
        return options.contains(.truncate_content_very_short)
    }
    
    var with_padding: Bool {
        return options.contains(.wide)
    }
    
    var preview: LinkViewRepresentable? {
        guard !blur_images,
              case .loaded(let preview) = preview_model.state,
              case .value(let cached) = preview else {
            return nil
        }
        
        return LinkViewRepresentable(meta: .linkmeta(cached))
    }
    
    func truncatedText(content: CompatibleText) -> some View {
        Group {
            if truncate_very_short {
                TruncatedText(text: content, maxChars: 140, show_show_more_button: !options.contains(.no_show_more))
                    .font(eventviewsize_to_font(size, font_size: damus_state.settings.font_size))
            }
            else if truncate {
                TruncatedText(text: content, show_show_more_button: !options.contains(.no_show_more))
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
        TranslateView(damus_state: damus_state, event: event, size: self.size, isAppleTranslationPopoverPresented: $isAppleTranslationPopoverPresented)
    }
    
    func previewView(links: [URL]) -> some View {
        Group {
            if let preview = self.preview, !blur_images {
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
    
    func fullscreen_preview(dismiss: @escaping () -> Void) -> some View {
        EmptyView()
    }
    
    func MainContent(artifacts: NoteArtifactsSeparated) -> some View {
        VStack(alignment: .leading) {
            if size == .selected {
                if with_padding {
                    SelectableText(damus_state: damus_state, event: self.event, attributedString: artifacts.content.attributed, size: self.size)
                        .padding(.horizontal)
                } else {
                    SelectableText(damus_state: damus_state, event: self.event, attributedString: artifacts.content.attributed, size: self.size)
                }
            } else {
                if with_padding {
                    truncatedText(content: artifacts.content)
                        .padding(.horizontal)
                } else {
                    truncatedText(content: artifacts.content)
                }
            }

            if !options.contains(.no_translate) && (size == .selected || TranslationService.isAppleTranslationPopoverSupported || damus_state.settings.auto_translate) {
                if with_padding {
                    translateView
                        .padding(.horizontal)
                } else {
                    translateView
                }
            }

            if artifacts.media.count > 0 {
                if (self.options.contains(.no_media)) {
                    EmptyView()
                } else if !damus_state.settings.media_previews && !load_media {
                    loadMediaButton(artifacts: artifacts)
                } else if !blur_images || (!blur_images && !damus_state.settings.media_previews && load_media) {
                    ImageCarousel(state: damus_state, evid: event.id, urls: artifacts.media) { dismiss in
                        fullscreen_preview(dismiss: dismiss)
                    }
                } else if blur_images || (blur_images && !damus_state.settings.media_previews && load_media) {
                    ZStack {
                        ImageCarousel(state: damus_state, evid: event.id, urls: artifacts.media) { dismiss in
                            fullscreen_preview(dismiss: dismiss)
                        }
                        BlurOverlayView(blur_images: $blur_images, artifacts: artifacts, size: size, damus_state: damus_state, parentView: .noteContentView)
                    }
                }
            }
            
            if artifacts.invoices.count > 0 {
                if with_padding {
                    invoicesView(invoices: artifacts.invoices)
                        .padding(.horizontal)
                } else {
                    invoicesView(invoices: artifacts.invoices)
                }
            }

            if damus_state.settings.media_previews, has_previews {
                if with_padding {
                    previewView(links: artifacts.links).padding(.horizontal)
                } else {
                    previewView(links: artifacts.links)
                }
            }

        }
    }

    var has_previews: Bool {
        !options.contains(.no_previews)
    }

    func loadMediaButton(artifacts: NoteArtifactsSeparated) -> some View {
        Button(action: {
            load_media = true
        }, label: {
            VStack(alignment: .leading) {
                HStack {
                    Image("images")
                    Text("Load media", comment: "Button to show media in note.")
                        .fontWeight(.bold)
                        .font(eventviewsize_to_font(size, font_size: damus_state.settings.font_size))
                }
                .padding(EdgeInsets(top: 5, leading: 10, bottom: 0, trailing: 10))
                
                ForEach(artifacts.media.indices, id: \.self) { index in
                    Divider()
                        .frame(height: 1)
                    switch artifacts.media[index] {
                    case .image(let url), .video(let url):
                        Text(abbreviateURL(url))
                            .font(eventviewsize_to_font(size, font_size: damus_state.settings.font_size))
                            .foregroundStyle(DamusColors.neutral6)
                            .multilineTextAlignment(.leading)
                            .padding(EdgeInsets(top: 0, leading: 10, bottom: 5, trailing: 10))
                    }
                }
            }
            .background(DamusColors.neutral1)
            .frame(minWidth: nil, maxWidth: .infinity, alignment: .center)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(DamusColors.neutral3, lineWidth: 1)
            )
        })
        .padding(.horizontal)
    }
    
    func load(force_artifacts: Bool = false) {
        if case .loading = damus_state.events.get_cache_data(event.id).artifacts_model.state {
            return
        }
        
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
                let arts = await ContentRenderer().render_note_content(ndb: damus_state.ndb, ev: event, profiles: damus_state.profiles, keypair: damus_state.keypair)
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
                if #available(iOS 17.4, macOS 14.4, *) {
                    MainContent(artifacts: separated)
#if !targetEnvironment(macCatalyst)
                        .translationPresentation(isPresented: $isAppleTranslationPopoverPresented, text: event.get_content(damus_state.keypair))
#endif
                } else {
                    MainContent(artifacts: separated)
                }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
    
    var body: some View {
        ArtifactContent
            .onReceive(handle_notify(.profile_updated)) { profile in
                guard let blockGroup = try? NdbBlockGroup.from(event: event, using: damus_state.ndb, and: damus_state.keypair) else {
                    return
                }
                let _: Int? = try? blockGroup.forEachBlock { index, block in
                    switch block {
                    case .mention(let m):
                        guard let typ = m.bech32_type else {
                            return .loopContinue
                        }
                        switch typ {
                        case .nprofile:
                            if m.bech32.nprofile.matches_pubkey(pk: profile.pubkey) {
                                load(force_artifacts: true)
                            }
                        case .npub:
                            if m.bech32.npub.matches_pubkey(pk: profile.pubkey) {
                                load(force_artifacts: true)
                            }
                        case .nevent: return .loopContinue
                        case .nrelay: return .loopContinue
                        case .nsec: return .loopContinue
                        case .note: return .loopContinue
                        case .naddr: return .loopContinue
                        }
                    case .text: return .loopContinue
                    case .hashtag: return .loopContinue
                    case .url: return .loopContinue
                    case .invoice: return .loopContinue
                    case .mention_index(_): return .loopContinue
                    }
                    return .loopContinue
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

struct BlurOverlayView: View {
    @Binding var blur_images: Bool
    let artifacts: NoteArtifactsSeparated?
    let size: EventViewKind?
    let damus_state: DamusState?
    let parentView: ParentViewType
    var body: some View {
        ZStack {
            
            Color.black
                .opacity(0.54)
            
            Blur()
            
            VStack(alignment: .center) {
                Image(systemName: "eye.slash")
                    .foregroundStyle(.white)
                    .bold()
                    .padding(EdgeInsets(top: 5, leading: 10, bottom: 0, trailing: 10))
                Text(NSLocalizedString("Media from someone you don't follow", comment: "Label on the image blur mask"))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Color.white)
                    .font(.title2)
                    .padding(EdgeInsets(top: 5, leading: 10, bottom: 0, trailing: 10))
                Button(NSLocalizedString("Tap to load", comment: "Label for button that allows user to dismiss media content warning and unblur the image")) {
                    blur_images = false
                }
                .buttonStyle(.bordered)
                .fontWeight(.bold)
                .foregroundStyle(.white)
                .padding(EdgeInsets(top: 5, leading: 10, bottom: 0, trailing: 10))
                
                if parentView == .noteContentView,
                   let artifacts = artifacts,
                   let size = size,
                   let damus_state = damus_state
                {
                    switch artifacts.media[0] {
                    case .image(let url), .video(let url):
                        Text(abbreviateURL(url, maxLength: 30))
                            .font(eventviewsize_to_font(size, font_size: damus_state.settings.font_size * 0.8))
                            .foregroundStyle(.white)
                            .multilineTextAlignment(.center)
                            .padding(EdgeInsets(top: 20, leading: 10, bottom: 5, trailing: 10))
                    }
                }
            }
        }
        .onTapGesture {
            blur_images = false
        }
    }
    
    enum ParentViewType {
        case noteContentView, longFormView
    }
}

struct NoteContentView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state
        let state2 = test_damus_state

        Group {
            VStack {
                NoteContentView(damus_state: state, event: test_note, blur_images: false, size: .normal, options: [])
            }
            .previewDisplayName("Short note")

            VStack {
                NoteContentView(damus_state: state, event: test_super_short_note, blur_images: true, size: .normal, options: [])
            }
            .previewDisplayName("Super short note")

            VStack {
                NoteContentView(damus_state: state, event: test_encoded_note_with_image!, blur_images: true, size: .normal, options: [])
            }
            .previewDisplayName("Note with image")

            VStack {
                NoteContentView(damus_state: state2, event: test_longform_event.event, blur_images: false, size: .normal, options: [.wide])
                    .border(Color.red)
            }
            .previewDisplayName("Long-form note")
            
            VStack {
                NoteContentView(damus_state: state, event: test_note, blur_images: false, size: .small, options: [.no_previews, .no_action_bar, .truncate_content_very_short, .no_show_more])
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .previewDisplayName("Small single-line note")
        }
    }
}

func separate_images(ndb: Ndb, ev: NostrEvent, keypair: Keypair) -> [MediaUrl]? {
    guard let blockGroup = try? NdbBlockGroup.from(event: ev, using: ndb, and: keypair) else {
        return nil
    }
    let urlBlocks: [URL] = (try? blockGroup.reduce(initialResult: Array<URL>()) { index, urls, block in
        switch block {
        case .url(let url):
            guard let parsed_url = URL(string: url.as_str()) else {
                return .loopContinue
            }
            
            if classify_url(parsed_url).is_img != nil {
                return .loopReturn(urls + [parsed_url])
            }
        default:
            break
        }
        return .loopContinue
    }) ?? []
    let mediaUrls = urlBlocks.map { MediaUrl.image($0) }
    return mediaUrls.isEmpty ? nil : mediaUrls
}
