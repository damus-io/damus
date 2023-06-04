//
//  NoteContentView.swift
//  damus
//
//  Created by William Casarin on 2022-05-04.
//

import SwiftUI
import LinkPresentation
import NaturalLanguage

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
    let show_images: Bool
    let size: EventViewKind
    let preview_height: CGFloat?
    let options: EventViewOptions

    @ObservedObject var artifacts_model: NoteArtifactsModel
    @ObservedObject var preview_model: PreviewModel
    
    var note_artifacts: NoteArtifacts {
        return self.artifacts_model.state.artifacts ?? .separated(.just_content(event.get_content(damus_state.keypair.privkey)))
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
    }
    
    var truncate: Bool {
        return options.contains(.truncate_content)
    }
    
    var with_padding: Bool {
        return options.contains(.pad_content)
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
                    .font(eventviewsize_to_font(size))
            } else {
                content.text
                    .font(eventviewsize_to_font(size))
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
                        .disabled(true)
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
                let arts = render_note_content(ev: event, profiles: damus_state.profiles, privkey: damus_state.keypair.privkey)
                self.artifacts_model.state = .loaded(arts)
            }
        }
    }
    
    func artifactPartsView(_ parts: [ArtifactPart]) -> some View {
        
        LazyVStack {
            ForEach(parts.indices, id: \.self) { ind in
                let part = parts[ind]
                switch part {
                case .text(let txt):
                    txt
                        .padding(.horizontal)
                case .invoice(let inv):
                    InvoiceView(our_pubkey: damus_state.pubkey, invoice: inv, settings: damus_state.settings)
                        .padding(.horizontal)
                case .media(let media):
                    Text("media \(media.url.absoluteString)")
                }
            }
        }
    }
    
    var ArtifactContent: some View {
        Group {
            switch self.note_artifacts {
            case .parts(let parts):
                artifactPartsView(parts.parts)
            case .separated(let separated):
                MainContent(artifacts: separated)
            }
        }
    }
    
    var body: some View {
        ArtifactContent
            .onReceive(handle_notify(.profile_updated)) { notif in
                let profile = notif.object as! ProfileUpdate
                let blocks = event.blocks(damus_state.keypair.privkey)
                for block in blocks.blocks {
                    switch block {
                    case .mention(let m):
                        if m.type == .pubkey && m.ref.ref_id == profile.pubkey {
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

func attributed_string_attach_icon(_ astr: inout AttributedString, img: UIImage) {
    let attachment = NSTextAttachment()
    attachment.image = img
    let attachmentString = NSAttributedString(attachment: attachment)
    let wrapped = AttributedString(attachmentString)
    astr.append(wrapped)
}

func url_str(_ url: URL) -> CompatibleText {
    var attributedString = AttributedString(stringLiteral: url.absoluteString)
    attributedString.link = url
    attributedString.foregroundColor = DamusColors.purple
    
    return CompatibleText(attributed: attributedString)
 }

func mention_str(_ m: Mention, profiles: Profiles) -> CompatibleText {
    switch m.type {
    case .pubkey:
        let pk = m.ref.ref_id
        let profile = profiles.lookup(id: pk)
        let disp = Profile.displayName(profile: profile, pubkey: pk).username.truncate(maxLength: 50)
        var attributedString = AttributedString(stringLiteral: "@\(disp)")
        attributedString.link = URL(string: "damus:\(encode_pubkey_uri(m.ref))")
        attributedString.foregroundColor = DamusColors.purple
        
        return CompatibleText(attributed: attributedString)
    case .event:
        let bevid = bech32_note_id(m.ref.ref_id) ?? m.ref.ref_id
        var attributedString = AttributedString(stringLiteral: "@\(abbrev_pubkey(bevid))")
        attributedString.link = URL(string: "damus:\(encode_event_id_uri(m.ref))")
        attributedString.foregroundColor = DamusColors.purple

        return CompatibleText(attributed: attributedString)
    }
}

struct NoteContentView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state()
        let content = "hi there ¯\\_(ツ)_/¯ https://jb55.com/s/Oct12-150217.png 5739a762ef6124dd.jpg"
        NoteContentView(damus_state: state, event: NostrEvent(content: content, pubkey: "pk"), show_images: true, size: .normal, options: [])
    }
}


enum NoteArtifacts {
    case separated(NoteArtifactsSeparated)
    case parts(NoteArtifactsParts)
    
    var images: [URL] {
        switch self {
        case .separated(let arts):
            return arts.images
        case .parts(let parts):
            return parts.parts.reduce(into: [URL]()) { acc, part in
                guard case .media(let m) = part,
                      case .image(let url) = m
                else { return }
                
                acc.append(url)
            }
        }
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

class NoteArtifactsParts {
    var parts: [ArtifactPart]
    var words: Int
    
    init(parts: [ArtifactPart], words: Int) {
        self.parts = parts
        self.words = words
    }
}

struct NoteArtifactsSeparated: Equatable {
    static func == (lhs: NoteArtifactsSeparated, rhs: NoteArtifactsSeparated) -> Bool {
        return lhs.content == rhs.content
    }
    
    let content: CompatibleText
    let words: Int
    let urls: [UrlType]
    let invoices: [Invoice]
    
    var media: [MediaUrl] {
        return urls.compactMap { url in url.is_media }
    }
    
    var images: [URL] {
        return urls.compactMap { url in url.is_img }
    }
    
    var links: [URL] {
        return urls.compactMap { url in url.is_link }
    }
    
    static func just_content(_ content: String) -> NoteArtifactsSeparated {
        let txt = CompatibleText(attributed: AttributedString(stringLiteral: content))
        return NoteArtifactsSeparated(content: txt, words: 0, urls: [], invoices: [])
    }
}

enum NoteArtifactState {
    case not_loaded
    case loading
    case loaded(NoteArtifacts)
    
    var artifacts: NoteArtifacts? {
        if case .loaded(let artifacts) = self {
            return artifacts
        }
        
        return nil
    }
    
    var should_preload: Bool {
        switch self {
        case .loaded:
            return false
        case .loading:
            return false
        case .not_loaded:
            return true
        }
    }
}

func note_artifact_is_separated(kind: NostrKind?) -> Bool {
    return kind != .longform
}

func render_note_content(ev: NostrEvent, profiles: Profiles, privkey: String?) -> NoteArtifacts {
    let blocks = ev.blocks(privkey)
    
    if ev.known_kind == .longform {
        return .parts(render_blocks_parted(blocks: blocks, profiles: profiles))
    }
    
    return .separated(render_blocks(blocks: blocks, profiles: profiles))
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

func render_blocks_parted(blocks bs: Blocks, profiles: Profiles) -> NoteArtifactsParts {
    let blocks = bs.blocks
    
    let new_parts = NoteArtifactsParts(parts: [], words: bs.words)
    
    return blocks.reduce(into: new_parts) { parts, block in
        
        switch block {
        case .mention(let m):
            guard let (last_ind, txt) = artifact_part_last_text_ind(parts: parts.parts) else {
                parts.parts.append(.text(mention_str(m, profiles: profiles).text))
                return
            }
            parts.parts[last_ind] = .text(txt + mention_str(m, profiles: profiles).text)
            
        case .text(let str):
            guard let (last_ind, txt) = artifact_part_last_text_ind(parts: parts.parts) else {
                // TODO: (jb55) md is longform specific
                let md = Markdown.parse(content: str)
                parts.parts.append(.text(Text(md)))
                return
            }
            
            parts.parts[last_ind] = .text(txt + Text(str))
            
        case .relay(let relay):
            guard let (last_ind, txt) = artifact_part_last_text_ind(parts: parts.parts) else {
                parts.parts.append(.text(Text(relay)))
                return
            }
            
            parts.parts[last_ind] = .text(txt + Text(relay))
            
        case .hashtag(let htag):
            guard let (last_ind, txt) = artifact_part_last_text_ind(parts: parts.parts) else {
                parts.parts.append(.text(hashtag_str(htag).text))
                return
            }
            
            parts.parts[last_ind] = .text(txt + hashtag_str(htag).text)
            
        case .invoice(let invoice):
            parts.parts.append(.invoice(invoice))
            return
            
        case .url(let url):
            let url_type = classify_url(url)
            switch url_type {
            case .media(let media_url):
                parts.parts.append(.media(media_url))
            case .link(let url):
                guard let (last_ind, txt) = artifact_part_last_text_ind(parts: parts.parts) else {
                    parts.parts.append(.text(url_str(url).text))
                    return
                }
                
                parts.parts[last_ind] = .text(txt + url_str(url).text)
            }
        }
    }
}

func reduce_text_block(blocks: [Block], ind: Int, txt: String, one_note_ref: Bool) -> CompatibleText {
    var trimmed = txt
    
    if let prev = blocks[safe: ind-1],
       case .url(let u) = prev,
       classify_url(u).is_media != nil {
        trimmed = " " + trim_prefix(trimmed)
    }
    
    if let next = blocks[safe: ind+1] {
        if case .url(let u) = next, classify_url(u).is_media != nil {
            trimmed = trim_suffix(trimmed)
        } else if case .mention(let m) = next, m.type == .event, one_note_ref {
            trimmed = trim_suffix(trimmed)
        }
    }
    
    return CompatibleText(stringLiteral: trimmed)
}

func render_blocks(blocks bs: Blocks, profiles: Profiles) -> NoteArtifactsSeparated {
    var invoices: [Invoice] = []
    var urls: [UrlType] = []
    let blocks = bs.blocks
    
    let one_note_ref = blocks
        .filter({ $0.is_note_mention })
        .count == 1
    
    var ind: Int = -1
    let txt: CompatibleText = blocks.reduce(CompatibleText()) { str, block in
        ind = ind + 1
        
        switch block {
        case .mention(let m):
            if m.type == .event && one_note_ref {
                return str
            }
            return str + mention_str(m, profiles: profiles)
        case .text(let txt):
            return str + reduce_text_block(blocks: blocks, ind: ind, txt: txt, one_note_ref: one_note_ref)
            
        case .relay(let relay):
            return str + CompatibleText(stringLiteral: relay)
            
        case .hashtag(let htag):
            return str + hashtag_str(htag)
        case .invoice(let invoice):
            invoices.append(invoice)
            return str
        case .url(let url):
            let url_type = classify_url(url)
            switch url_type {
            case .media:
                urls.append(url_type)
                return str
            case .link(let url):
                urls.append(url_type)
                return str + url_str(url)
            }
        }
    }

    return NoteArtifactsSeparated(content: txt, words: bs.words, urls: urls, invoices: invoices)
}

enum MediaUrl {
    case image(URL)
    case video(URL)
    
    var url: URL {
        switch self {
        case .image(let url):
            return url
        case .video(let url):
            return url
        }
    }
}

enum UrlType {
    case media(MediaUrl)
    case link(URL)
    
    var url: URL {
        switch self {
        case .media(let media_url):
            switch media_url {
            case .image(let url):
                return url
            case .video(let url):
                return url
            }
        case .link(let url):
            return url
        }
    }
    
    var is_video: URL? {
        switch self {
        case .media(let media_url):
            switch media_url {
            case .image:
                return nil
            case .video(let url):
                return url
            }
        case .link:
            return nil
        }
    }
    
    var is_img: URL? {
        switch self {
        case .media(let media_url):
            switch media_url {
            case .image(let url):
                return url
            case .video:
                return nil
            }
        case .link:
            return nil
        }
    }
    
    var is_link: URL? {
        switch self {
        case .media:
            return nil
        case .link(let url):
            return url
        }
    }
    
    var is_media: MediaUrl? {
        switch self {
        case .media(let murl):
            return murl
        case .link:
            return nil
        }
    }
}

func classify_url(_ url: URL) -> UrlType {
    let str = url.lastPathComponent.lowercased()
    
    if str.hasSuffix(".png") || str.hasSuffix(".jpg") || str.hasSuffix(".jpeg") || str.hasSuffix(".gif") || str.hasSuffix(".webp") {
        return .media(.image(url))
    }
    
    if str.hasSuffix(".mp4") || str.hasSuffix(".mov") {
        return .media(.video(url))
    }
    
    return .link(url)
}

func lookup_cached_preview_size(previews: PreviewCache, evid: String) -> CGFloat? {
    guard case .value(let cached) = previews.lookup(evid) else {
        return nil
    }
    
    guard let height = cached.intrinsic_height else {
        return nil
    }
    
    return height
}

// trim suffix whitespace and newlines
func trim_suffix(_ str: String) -> String {
    return str.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
}

// trim prefix whitespace and newlines
func trim_prefix(_ str: String) -> String {
    return str.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
}
