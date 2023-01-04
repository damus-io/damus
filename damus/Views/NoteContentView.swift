//
//  NoteContentView.swift
//  damus
//
//  Created by William Casarin on 2022-05-04.
//

import SwiftUI
import LinkPresentation

struct NoteArtifacts {
    let content: String
    let images: [URL]
    let invoices: [Invoice]
    let links: [URL]
    
    static func just_content(_ content: String) -> NoteArtifacts {
        NoteArtifacts(content: content, images: [], invoices: [], links: [])
    }
}

func render_note_content(ev: NostrEvent, profiles: Profiles, privkey: String?) -> NoteArtifacts {
    let blocks = ev.blocks(privkey)
    var invoices: [Invoice] = []
    var img_urls: [URL] = []
    var link_urls: [URL] = []
    let txt = blocks.reduce("") { str, block in
        switch block {
        case .mention(let m):
            return str + mention_str(m, profiles: profiles)
        case .text(let txt):
            return str + txt
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
                return str + url.absoluteString
            }
        }
    }
    
    return NoteArtifacts(content: txt, images: img_urls, invoices: invoices, links: link_urls)
}

func is_image_url(_ url: URL) -> Bool {
    let str = url.lastPathComponent
    return str.hasSuffix("png") || str.hasSuffix("jpg") || str.hasSuffix("jpeg") || str.hasSuffix("gif")
}

struct NoteContentView: View {
    let privkey: String?
    let event: NostrEvent
    let profiles: Profiles
    let previews: PreviewCache
    
    let show_images: Bool
    
    @State var artifacts: NoteArtifacts
    
    @State var preview: LinkViewRepresentable? = nil
    let size: EventViewKind
    
    func MainContent() -> some View {
        return VStack(alignment: .leading) {
            Text(Markdown.parse(content: artifacts.content))
                .font(eventviewsize_to_font(size))

            if show_images && artifacts.images.count > 0 {
                ImageCarousel(urls: artifacts.images)
            } else if !show_images && artifacts.images.count > 0 {
                ImageCarousel(urls: artifacts.images)
                    .blur(radius: 10)
                    .overlay {
                        Rectangle()
                            .opacity(0.50)
                    }
                    .cornerRadius(10)
            }
            if artifacts.invoices.count > 0 {
                InvoicesView(invoices: artifacts.invoices)
            }
            
            if show_images, self.preview != nil {
                self.preview
            } else {
                ForEach(artifacts.links, id:\.self) { link in
                    if let url = link {
                        LinkViewRepresentable(meta: .url(url))
                            .frame(height: 50)
                    }
                }
            }
        }
    }
    
    var body: some View {
        MainContent()
            .onAppear() {
                self.artifacts = render_note_content(ev: event, profiles: profiles, privkey: privkey)
            }
            .onReceive(handle_notify(.profile_updated)) { notif in
                let profile = notif.object as! ProfileUpdate
                let blocks = event.blocks(privkey)
                for block in blocks {
                    switch block {
                    case .mention(let m):
                        if m.type == .pubkey && m.ref.ref_id == profile.pubkey {
                            self.artifacts = render_note_content(ev: event, profiles: profiles, privkey: privkey)
                        }
                    case .text: return
                    case .hashtag: return
                    case .url: return
                    case .invoice: return
                    }
                }
            }
            .task {
                if let preview = previews.lookup(self.event.id) {
                    switch preview {
                    case .value(let view):
                        self.preview = view
                    case .failed:
                        // don't try to refetch meta if we've failed
                        return
                    }
                }
                
                if show_images, artifacts.links.count == 1 {
                    let meta = await getMetaData(for: artifacts.links.first!)
                    
                    let view = meta.map { LinkViewRepresentable(meta: .linkmeta($0)) }
                    previews.store(evid: self.event.id, preview: view)
                    self.preview = view
                }
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

func hashtag_str(_ htag: String) -> String {
    return "[#\(htag)](nostr:t:\(htag))"
}

func mention_str(_ m: Mention, profiles: Profiles) -> String {
    switch m.type {
    case .pubkey:
        let pk = m.ref.ref_id
        let profile = profiles.lookup(id: pk)
        let disp = Profile.displayName(profile: profile, pubkey: pk)
        return "[@\(disp)](nostr:\(encode_pubkey_uri(m.ref)))"
    case .event:
        let bevid = bech32_note_id(m.ref.ref_id) ?? m.ref.ref_id
        return "[@\(abbrev_pubkey(bevid))](nostr:\(encode_event_id_uri(m.ref)))"
    }
}


struct NoteContentView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state()
        let content = "hi there ¯\\_(ツ)_/¯ https://jb55.com/s/Oct12-150217.png 5739a762ef6124dd.jpg"
        let artifacts = NoteArtifacts(content: content, images: [], invoices: [], links: [])
        NoteContentView(privkey: "", event: NostrEvent(content: content, pubkey: "pk"), profiles: state.profiles, previews: PreviewCache(), show_images: true, artifacts: artifacts, size: .normal)
    }
}
