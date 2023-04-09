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
    
    @State var tapped_universal_link: URL?
    @State var active_profile: String? = nil
    @State var active_search: NostrFilter? = nil
    @State var active_event: NostrEvent? = nil
    @State var profile_open: Bool = false
    @State var thread_open: Bool = false
    @State var search_open: Bool = false
    
    @State var artifacts: NoteArtifacts
    @State var preview: LinkViewRepresentable?
    
    init(damus_state: DamusState, event: NostrEvent, show_images: Bool, size: EventViewKind, artifacts: NoteArtifacts, options: EventViewOptions) {
        self.damus_state = damus_state
        self.event = event
        self.show_images = show_images
        self.size = size
        self.options = options
        self.preview_height = lookup_cached_preview_size(previews: damus_state.previews, evid: event.id)
        self._preview = State(initialValue: load_cached_preview(previews: damus_state.previews, evid: event.id))
        if let cache = damus_state.events.lookup_artifacts(evid: event.id) {
            self._artifacts = State(initialValue: cache)
        } else {
            let artifacts = render_note_content(ev: event, profiles: damus_state.profiles, privkey: damus_state.keypair.privkey)
            damus_state.events.store_artifacts(evid: event.id, artifacts: artifacts)
            self._artifacts = State(initialValue: artifacts)
        }
    }
    
    var truncate: Bool {
        return options.contains(.truncate_content)
    }
    
    var with_padding: Bool {
        return options.contains(.pad_content)
    }
    
    var truncatedText: some View {
        TruncatedText(text: artifacts.content, size: size, tappedUniversalLink: $tapped_universal_link)
    }
    
    var invoicesView: some View {
        InvoicesView(our_pubkey: damus_state.keypair.pubkey, invoices: artifacts.invoices)
    }

    var translateView: some View {
        TranslateView(damus_state: damus_state, event: event, size: self.size, tappedUniversalLink: $tapped_universal_link)
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
            } else if let link = renderableLinks.first {
                LinkViewRepresentable(meta: .url(link))
                    .frame(height: 50)
            }
        }
    }
    
    var MainContent: some View {
        VStack(alignment: .leading) {
            if truncate {
                if with_padding {
                    truncatedText
                        .padding(.horizontal)
                } else {
                    truncatedText
                }
            } else {
                let text = SelectableText(attributedString: artifacts.content.attributed, size: size, tappedUniversalLink: $tapped_universal_link)
                if with_padding {
                    text
                        .padding(.horizontal)
                } else {
                    text
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
                ImageCarousel(previews: damus_state.previews, evid: event.id, urls: artifacts.images)
            } else if !show_images && artifacts.images.count > 0 {
                ZStack {
                    ImageCarousel(previews: damus_state.previews, evid: event.id, urls: artifacts.images)
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
    
    var MaybeThreadView: some View {
        Group {
            if let active_event {
                let thread = ThreadModel(event: active_event, damus_state: damus_state)
                ThreadView(state: damus_state, thread: thread)
            } else {
                EmptyView()
            }
        }
    }
    
    var MaybeSearchView: some View {
        Group {
            if let search = self.active_search {
                SearchView(appstate: damus_state, search: SearchModel(contacts: damus_state.contacts, pool: damus_state.pool, search: search))
            } else {
                EmptyView()
            }
        }
    }
    
    var MaybeProfileView: some View {
        Group {
            if let pk = self.active_profile {
                let profile_model = ProfileModel(pubkey: pk, damus: damus_state)
                let followers = FollowersModel(damus_state: damus_state, target: pk)
                ProfileView(damus_state: damus_state, profile: profile_model, followers: followers)
            } else {
                EmptyView()
            }
        }
    }
    
    var body: some View {
        VStack {
            NavigationLink(destination: MaybeProfileView, isActive: $profile_open) {
                EmptyView()
            }
            NavigationLink(destination: MaybeThreadView, isActive: $thread_open) {
                EmptyView()
            }
            NavigationLink(destination: MaybeSearchView, isActive: $search_open) {
                EmptyView()
            }
            MainContent
        }
        .onReceive(handle_notify(.profile_updated)) { notif in
            let profile = notif.object as! ProfileUpdate
            let blocks = event.blocks(damus_state.keypair.privkey)
            for block in blocks {
                switch block {
                case .mention(let m):
                    if m.type == .pubkey && m.ref.ref_id == profile.pubkey {
                        self.artifacts = render_note_content(ev: event, profiles: damus_state.profiles, privkey: damus_state.keypair.privkey)
                    }
                case .text: return
                case .hashtag: return
                case .url: return
                case .invoice: return
                }
            }
        }
        .onChange(of: tapped_universal_link) { value in
            guard let url = value, let link = decode_nostr_uri(url.absoluteString) else {
                return
            }
            
            switch link {
            case .ref(let ref):
                if ref.key == "p" {
                    active_profile = ref.ref_id
                    profile_open = true
                } else if ref.key == "e" {
                    find_event(state: damus_state, evid: ref.ref_id, search_type: .event, find_from: nil) { ev in
                        if let ev {
                            active_event = ev
                        }
                    }
                    thread_open = true
                }
            case .filter(let filt):
                active_search = filt
                search_open = true
            }
        }
        .onAppear {
            tapped_universal_link = nil
            active_event = nil
            thread_open = false
        }
        .task {
            guard self.preview == nil else {
                return
            }
            
            if show_images, renderableLinks.count == 1 {
                let meta = await getMetaData(for: renderableLinks.first!)
                
                damus_state.previews.store(evid: self.event.id, preview: meta)
                guard case .value(let cached) = damus_state.previews.lookup(self.event.id) else {
                    return
                }
                let view = LinkViewRepresentable(meta: .linkmeta(cached))
                
                self.preview = view
            }
            
        }
    }
    
    private var renderableLinks: [URL] {
        artifacts.links.filter { link in
            guard let components = URLComponents(url: link, resolvingAgainstBaseURL: false) else {
                return true
            }
            return components.host != "damus.io" || (!components.path.hasPrefix("/note") && !components.path.hasPrefix("/npub"))
        }
    }
    
    func getMetaData(for url: URL) async -> LPLinkMetadata? {
        // iOS 15 is crashing for some reason
        guard #available(iOS 16, *) else {
            return nil
        }
        
        let provider = LPMetadataProvider()
        
        do {
            return try await provider.startFetchingMetadata(for: url)
        } catch {
            return nil
        }
    }
}

enum ImageName {
    case systemImage(String)
    case image(String)
}

func attributed_string_attach_icon(_ astr: inout AttributedString, img: UIImage) {
    let attachment = NSTextAttachment()
    attachment.image = img
    let attachmentString = NSAttributedString(attachment: attachment)
    let wrapped = AttributedString(attachmentString)
    astr.append(wrapped)
}

func url_str(_ url: URL, representation: String? = nil) -> CompatibleText {
    var attributedString = AttributedString(representation ?? url.absoluteString)
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
        let txt = CompatibleText(attributed: AttributedString(stringLiteral: content))
        let artifacts = NoteArtifacts(content: txt, images: [], invoices: [], links: [])
        NoteContentView(damus_state: state, event: NostrEvent(content: content, pubkey: "pk"), show_images: true, size: .normal, artifacts: artifacts, options: [])
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

func render_note_content(ev: NostrEvent, profiles: Profiles, privkey: String?) -> NoteArtifacts {
    let blocks = ev.blocks(privkey)
    
    return render_blocks(blocks: blocks, profiles: profiles, privkey: privkey)
}

func render_blocks(blocks: [Block], profiles: Profiles, privkey: String?) -> NoteArtifacts {
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
                if let decoded = decode_universal_link(url.absoluteString) {
                    switch decoded {
                    case .ref(let ref):
                        if ref.key == "p" {
                            return str + url_str(url, representation: url.absoluteString.replacingOccurrences(of: "https://damus.io/npub", with: "@npub"))
                        } else if ref.key == "e" {
                            return str + url_str(url, representation: url.absoluteString.replacingOccurrences(of: "https://damus.io/note", with: "@note"))
                        } else {
                            return str + url_str(url)
                        }
                    default:
                        return str + url_str(url)
                    }
                } else {
                    return str + url_str(url)
                }
            }
        }
    }

    return NoteArtifacts(content: txt, images: img_urls, invoices: invoices, links: link_urls)
}

func is_image_url(_ url: URL) -> Bool {
    let str = url.lastPathComponent.lowercased()
    let isUrl = str.hasSuffix(".png") || str.hasSuffix(".jpg") || str.hasSuffix(".jpeg") || str.hasSuffix(".gif")
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
    

func load_cached_preview(previews: PreviewCache, evid: String) -> LinkViewRepresentable? {
    guard case .value(let meta) = previews.lookup(evid) else {
        return nil
    }
    
    return LinkViewRepresentable(meta: .linkmeta(meta))
}

// trim suffix whitespace and newlines
func trim_suffix(_ str: String) -> String {
    return str.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression)
}

// trim prefix whitespace and newlines
func trim_prefix(_ str: String) -> String {
    return str.replacingOccurrences(of: "^\\s+", with: "", options: .regularExpression)
}
