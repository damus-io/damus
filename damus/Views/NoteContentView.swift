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
    
    var artifacts: NoteArtifacts {
        return self.artifacts_model.state.artifacts ?? .just_content(event.get_content(damus_state.keypair.privkey))
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
    
    var truncatedText: some View {
        Group {
            if truncate {
                TruncatedText(text: artifacts.content)
                    .font(eventviewsize_to_font(size))
            } else {
                artifacts.content.text
                    .font(eventviewsize_to_font(size))
            }
        }
    }
    
    var invoicesView: some View {
        InvoicesView(our_pubkey: damus_state.keypair.pubkey, invoices: artifacts.invoices, settings: damus_state.settings)
    }

    var translateView: some View {
        TranslateView(damus_state: damus_state, event: event, size: self.size)
    }
    
    var previewView: some View {
        Group {
            if let preview = self.preview, show_images {
                if let preview_height {
                    preview
                        .frame(height: preview_height)
                } else {
                    preview
                }
            } else if let link = artifacts.links.first {
                LinkViewRepresentable(meta: .url(link))
                    .frame(height: 50)
            }
        }
    }
    
    var MainContent: some View {
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
                    truncatedText
                        .padding(.horizontal)
                } else {
                    truncatedText
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

            if show_images && artifacts.images.count > 0 {
                ImageCarousel(state: damus_state, evid: event.id, urls: artifacts.images)
            } else if !show_images && artifacts.images.count > 0 {
                ZStack {
                    ImageCarousel(state: damus_state, evid: event.id, urls: artifacts.images)
                    Blur()
                        .disabled(true)
                }
                //.cornerRadius(10)
            }
            
            if artifacts.invoices.count > 0 {
                if with_padding {
                    invoicesView
                        .padding(.horizontal)
                } else {
                    invoicesView
                }
            }
            
            if with_padding {
                previewView.padding(.horizontal)
            } else {
                previewView
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
    
    var body: some View {
        MainContent
            .onReceive(handle_notify(.profile_updated)) { notif in
                let profile = notif.object as! ProfileUpdate
                let blocks = event.blocks(damus_state.keypair.privkey)
                for block in blocks {
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
        let disp = Profile.displayName(profile: profile, pubkey: pk).username
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

struct NoteArtifacts: Equatable {
    static func == (lhs: NoteArtifacts, rhs: NoteArtifacts) -> Bool {
        return lhs.content == rhs.content
    }
    
    let content: CompatibleText
    let images: [URL]
    let invoices: [Invoice]
    let links: [URL]
    
    static func just_content(_ content: String) -> NoteArtifacts {
        let txt = CompatibleText(attributed: AttributedString(stringLiteral: content))
        return NoteArtifacts(content: txt, images: [], invoices: [], links: [])
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

func render_note_content(ev: NostrEvent, profiles: Profiles, privkey: String?) -> NoteArtifacts {
    let blocks = ev.blocks(privkey)
    
    return render_blocks(blocks: blocks, profiles: profiles)
}

func render_blocks(blocks: [Block], profiles: Profiles) -> NoteArtifacts {
    var invoices: [Invoice] = []
    var img_urls: [URL] = []
    var link_urls: [URL] = []
    
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
            var trimmed = txt
            if let prev = blocks[safe: ind-1], case .url(let u) = prev, is_image_url(u) {
                trimmed = " " + trim_prefix(trimmed)
            }
            
            if let next = blocks[safe: ind+1] {
                if case .url(let u) = next, is_image_url(u) {
                    trimmed = trim_suffix(trimmed)
                } else if case .mention(let m) = next, m.type == .event, one_note_ref {
                    trimmed = trim_suffix(trimmed)
                }
            }
            
            return str + CompatibleText(stringLiteral: trimmed)
        case .relay(let relay):
            return str + CompatibleText(stringLiteral: relay)
            
        case .hashtag(let htag):
            return str + hashtag_str(htag)
        case .invoice(let invoice):
            invoices.append(invoice)
            return str
        case .url(let url):
            // Handle Image URLs
            if is_image_url(url) {
                // Append Image
                img_urls.append(url)
                return str
            } else {
                link_urls.append(url)
                return str + url_str(url)
            }
        }
    }

    return NoteArtifacts(content: txt, images: img_urls, invoices: invoices, links: link_urls)
}

func is_image_url(_ url: URL) -> Bool {
    let str = url.lastPathComponent.lowercased()
    let isUrl = str.hasSuffix(".png") || str.hasSuffix(".jpg") || str.hasSuffix(".jpeg") || str.hasSuffix(".gif") || str.hasSuffix(".webp")
    return isUrl
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
