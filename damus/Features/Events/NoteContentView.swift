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
import UIKit

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
    @State private var showLinksDropdown = false
    let size: EventViewKind
    let preview_height: CGFloat?
    let options: EventViewOptions
    let highlightTerms: [String]
    let textColor: Color?

    @State var isAppleTranslationPopoverPresented: Bool = false

    @ObservedObject var artifacts_model: NoteArtifactsModel
    @ObservedObject var preview_model: PreviewModel
    @ObservedObject var settings: UserSettingsStore

    var note_artifacts: NoteArtifacts {
        if damus_state.settings.undistractMode {
            return .separated(.just_content(Undistractor.makeGibberish(text: event.get_content(damus_state.keypair))))
        }
        let artifacts = self.artifacts_model.state.artifacts ?? .separated(.just_content(event.get_content(damus_state.keypair)))
        // Debug logging for DM content
        if event.known_kind == .dm_chat || event.known_kind == .dm {
            if case .separated(let sep) = artifacts {
                print("[DM-DEBUG] NoteContentView: kind=\(event.kind) charCount=\(sep.content.attributed.characters.count) content='\(String(sep.content.attributed.characters.prefix(50)))'")
            }
        }
        return artifacts
    }
    
    init(damus_state: DamusState, event: NostrEvent, blur_images: Bool, size: EventViewKind, options: EventViewOptions, highlightTerms: [String] = [], textColor: Color? = nil) {
        self.damus_state = damus_state
        self.event = event
        self.blur_images = blur_images
        self.size = size
        self.options = options
        self.highlightTerms = highlightTerms
        self.textColor = textColor
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
        guard case .loaded(let preview) = preview_model.state,
              case .value(let cached) = preview else {
            return nil
        }

        // If either
        // (1) the blur images setting is enabled
        // (2) the media previews setting is disabled
        // (3) this note content view does not display media
        // then do not show media in the link preview.
        if blur_images || !damus_state.settings.media_previews || self.options.contains(.no_media) {
            return linkPreviewWithNoMedia(cached)
        }

        // If media is already being shown, do not show media in the link preview
        // to avoid taking up additional screen space.
        if case let .separated(separated) = note_artifacts, !separated.media.isEmpty && !self.options.contains(.no_media) {
            return linkPreviewWithNoMedia(cached)
        }

        return LinkViewRepresentable(meta: .linkmeta(cached))
    }

    // Creates a LinkViewRepresentable without media previews.
    func linkPreviewWithNoMedia(_ cached: CachedMetadata) -> LinkViewRepresentable? {
        let linkMetadata = LPLinkMetadata()

        linkMetadata.originalURL = cached.meta.originalURL
        linkMetadata.title = cached.meta.title
        linkMetadata.url = cached.meta.url

        return LinkViewRepresentable(meta: .linkmeta(CachedMetadata(meta: linkMetadata)))
    }

    func truncatedText(content: CompatibleText) -> some View {
        Group {
            if truncate_very_short {
                TruncatedText(text: content, maxChars: 140, show_show_more_button: !options.contains(.no_show_more))
                    .font(eventviewsize_to_font(size, font_size: damus_state.settings.font_size))
                    .foregroundStyle(textColor ?? Color.primary)
            }
            else if truncate {
                TruncatedText(text: content, show_show_more_button: !options.contains(.no_show_more))
                    .font(eventviewsize_to_font(size, font_size: damus_state.settings.font_size))
                    .foregroundStyle(textColor ?? Color.primary)
            } else {
                content.text
                    .font(eventviewsize_to_font(size, font_size: damus_state.settings.font_size))
                    .foregroundStyle(textColor ?? Color.primary)
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
            if let preview = self.preview {
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
        let contentToRender = highlightedContent(artifacts.content)

        // Debug: log rendering path for DMs
        if event.known_kind == .dm_chat || event.known_kind == .dm {
            print("[DM-DEBUG] MainContent: size=\(size) charCount=\(artifacts.content.attributed.characters.count) truncate=\(truncate) with_padding=\(with_padding)")
        }

        return VStack(alignment: .leading) {
            if artifacts.content.attributed.characters.count != 0 {
                if size == .selected {
                    if with_padding {
                        SelectableText(damus_state: damus_state, event: self.event, attributedString: contentToRender.attributed, size: self.size)
                            .padding(.horizontal)
                    } else {
                        SelectableText(damus_state: damus_state, event: self.event, attributedString: contentToRender.attributed, size: self.size)
                    }
                } else {
                    if with_padding {
                        truncatedText(content: contentToRender)
                            .padding(.horizontal)
                    } else {
                        truncatedText(content: contentToRender)
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

            if has_previews {
                if with_padding {
                    previewView(links: artifacts.links).padding(.horizontal)
                } else {
                    previewView(links: artifacts.links)
                }
            }

        }
        .padding(.top, artifacts.content.attributed.characters.count == 0 ? 7 : 0)
    }

    var has_previews: Bool {
        !options.contains(.no_previews)
    }
    
    func loadMediaButton(artifacts: NoteArtifactsSeparated) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                
                Button(action: {
                    load_media = true
                }) {
                    HStack(spacing: 10) {
                        ZStack(alignment: .topTrailing) {
                            Image("images")
                                .foregroundStyle(DamusColors.neutral6)
                                .accessibilityHidden(true)
                            
                            if artifacts.media.count > 1 {
                                Text("\(artifacts.media.count)")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(
                                        Capsule()
                                            .fill(DamusColors.neutral6)
                                    )
                                    .offset(x: 6, y: -6)
                                    .accessibilityHidden(true)
                            }
                        }
                        
                        Text("Load \(artifacts.media.count) \(pluralizedString(key: "media_count", count: artifacts.media.count))")
                            .font(eventviewsize_to_font(size, font_size: damus_state.settings.font_size))
                            .foregroundStyle(DamusColors.neutral6)
                        
                        Spacer()

                    }
                    .padding(.vertical, 12)
                    .padding(.leading, 14)
                    .padding(.trailing, 8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())

                Rectangle()
                    .fill(DamusColors.neutral3)
                    .frame(width: 1)
                    .padding(.vertical, 8)
                
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        showLinksDropdown.toggle()
                    }
                }) {
                    Image(systemName: showLinksDropdown ? "chevron.up.circle.fill" : "chevron.down.circle")
                        .font(.system(size: 16))
                        .foregroundStyle(DamusColors.neutral6)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PlainButtonStyle())
                .accessibilityLabel(NSLocalizedString(showLinksDropdown ? "Hide media links" : "Show media links", comment: "Accessibility label for toggle button to show/hide media link list"))
            }
            .background(
                 RoundedRectangle(cornerRadius: 10)
                     .fill(DamusColors.neutral1.opacity(0.6))
                     .overlay(
                         RoundedRectangle(cornerRadius: 10)
                             .stroke(DamusColors.neutral3, lineWidth: 1)
                     )
                     .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
             )
             
            if showLinksDropdown {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(artifacts.media.enumerated()), id: \.offset) { index, mediaItem in
                        if index > 0 {
                            Divider()
                                .background(DamusColors.neutral3)
                        }
                        
                        mediaLinkRow(for: mediaItem, at: index)
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(DamusColors.neutral1.opacity(0.4))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(DamusColors.neutral3, lineWidth: 1)
                        )
                        .shadow(color: .black.opacity(0.05), radius: 2, y: 1)
                )
                .padding(.top, 6)
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .scale(scale: 0.95, anchor: .top)),
                    removal: .opacity
                ))
            }
        }
        .padding(.horizontal)
    }
    
    @concurrent
    func streamProfiles() async throws {
        var mentionPubkeys: Set<Pubkey> = []
        let event = await self.event.clone()
        try await NdbBlockGroup.borrowBlockGroup(event: event, using: damus_state.ndb, and: damus_state.keypair, borrow: { blockGroup in
            blockGroup.forEachBlock({ _, block in
                guard let pubkey = block.mentionPubkey(tags: event.tags) else {
                    return .loopContinue
                }
                mentionPubkeys.insert(pubkey)
                return .loopContinue
            })
        })
        
        if mentionPubkeys.isEmpty {
            return
        }

        // Only re-render on network updates, not cached profiles.
        // Initial render already uses cached profile data via the view hierarchy.
        for await profile in await damus_state.nostrNetwork.profilesManager.streamProfiles(pubkeys: mentionPubkeys, yieldCached: false) {
            await load(force_artifacts: true)
        }
    }

    @ViewBuilder
    private func mediaLinkRow(for mediaItem: MediaUrl, at index: Int) -> some View {
        switch mediaItem {
        case .image(let url), .video(let url):
            Button(action: {
                load_media = true
            }) {
                HStack(spacing: 10) {

                    Image(systemName: "photo.circle.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(DamusColors.neutral6)
                        .accessibilityHidden(true)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text(abbreviateURL(url))
                            .font(.system(size: 13))
                            .foregroundStyle(DamusColors.neutral6)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        
                        if let domain = url.host {
                            Text(domain)
                                .font(.system(size: 11))
                                .foregroundStyle(DamusColors.neutral6)
                        }
                    }
                    
                    Spacer(minLength: 8)
                    
                    HStack(spacing: 12) {
                        Button(action: {
                            UIPasteboard.general.string = url.absoluteString
                            let impactFeedback = UIImpactFeedbackGenerator(style: .light)
                            impactFeedback.impactOccurred()
                        }) {
                            Image(systemName: "doc.on.doc")
                                .font(.system(size: 14))
                                .foregroundStyle(DamusColors.neutral6)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityLabel(NSLocalizedString("Copy media link", comment: "Accessibility label for copy media link button"))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                )
            }
            .buttonStyle(PlainButtonStyle())
            .accessibilityLabel(NSLocalizedString("Load \(abbreviateURL(url))", comment: "Accessibility label for button to load specific media item"))
        }
    }
    
    func load(force_artifacts: Bool = false) {
        if case .loading = damus_state.events.get_cache_data(event.id).artifacts_model.state {
            return
        }
        
        // always reload artifacts on load
        let plan = get_preload_plan(ndb: damus_state.ndb, evcache: damus_state.events, ev: event, our_keypair: damus_state.keypair, settings: damus_state.settings)
        
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
                // Note: Do NOT apply .fixedSize to longform content - it prevents async images from expanding
                // Limit line length to ~600pt for optimal readability (50-75 chars per line)
                LongformMarkdownView(
                    markdown: md.markdown,
                    disableAnimation: damus_state.settings.disable_animation,
                    lineHeightMultiplier: damus_state.settings.longform_line_height,
                    sepiaEnabled: damus_state.settings.longform_sepia_mode
                )
            case .separated(let separated):
                if #available(iOS 17.4, macOS 14.4, *) {
                    MainContent(artifacts: separated)
#if !targetEnvironment(macCatalyst)
                        .translationPresentation(isPresented: $isAppleTranslationPopoverPresented, text: event.get_content(damus_state.keypair))
#endif
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    MainContent(artifacts: separated)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    var normalizedHighlightTerms: [String] {
        var output: [String] = []
        var seen = Set<String>()

        let preparedTerms = highlightTerms
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .flatMap { term -> [String] in
                if term.hasPrefix("#") {
                    let stripped = String(term.dropFirst())
                    return [term, stripped]
                }
                return [term]
            }

        for term in preparedTerms {
            let lower = term.lowercased()
            if !lower.isEmpty && seen.insert(lower).inserted {
                output.append(lower)
            }
        }

        return output
    }

    func highlightedContent(_ content: CompatibleText) -> CompatibleText {
        guard !normalizedHighlightTerms.isEmpty else { return content }

        var attributed = content.attributed
        highlightAttributedString(&attributed)
        return CompatibleText(attributed: attributed)
    }

    func highlightAttributedString(_ attributed: inout AttributedString) {
        for term in normalizedHighlightTerms {
            var searchStart = attributed.startIndex

            while let range = attributed[searchStart...].range(of: term, options: .caseInsensitive) {
                attributed[range].backgroundColor = DamusColors.highlight
                searchStart = range.upperBound
            }
        }
    }

    var body: some View {
        ArtifactContent
            .task {
                try? await streamProfiles()
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
    return try? NdbBlockGroup.borrowBlockGroup(event: ev, using: ndb, and: keypair, borrow: { blockGroup in
        let urlBlocks: [URL] = (blockGroup.reduce(initialResult: Array<URL>()) { index, urls, block in
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
    })
}

extension NdbBlock {
    func mentionPubkey(tags: Tags) -> Pubkey? {
        switch self {
        case .mention(let mentionBlock):
            guard let mention = MentionRef(block: mentionBlock) else {
                return nil
            }
            return mention.pubkey
        case .mention_index(let mentionIndex):
            let tagPosition = Int(mentionIndex)
            guard tagPosition >= 0, tagPosition < tags.count else {
                return nil
            }
            guard let mention = MentionRef.from_tag(tag: tags[tagPosition]) else {
                return nil
            }
            return mention.pubkey
        default:
            return nil
        }
    }
}
