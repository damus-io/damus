//
//  NoteContentView.swift
//  damus
//
//  Created by William Casarin on 2022-05-04.
//

import SwiftUI

struct NoteArtifacts {
    let content: String
    let images: [URL]
    let invoices: [Invoice]
    
    static func just_content(_ content: String) -> NoteArtifacts {
        NoteArtifacts(content: content, images: [], invoices: [])
    }
}

func render_note_content(ev: NostrEvent, profiles: Profiles, privkey: String?) -> NoteArtifacts {
    let blocks = ev.blocks(privkey)
    var invoices: [Invoice] = []
    var img_urls: [URL] = []
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
            if is_image_url(url) {
                img_urls.append(url)
            }
            return str + url.absoluteString
        }
    }
    
    return NoteArtifacts(content: txt, images: img_urls, invoices: invoices)
}

func is_image_url(_ url: URL) -> Bool {
    let str = url.lastPathComponent
    return str.hasSuffix("png") || str.hasSuffix("jpg") || str.hasSuffix("jpeg") || str.hasSuffix("gif")
}

struct NoteContentView: View {
    let privkey: String?
    let event: NostrEvent
    let profiles: Profiles
    
    let show_images: Bool
    
    @State var artifacts: NoteArtifacts
    
    let size: EventViewKind
    
    func MainContent() -> some View {
        return VStack(alignment: .leading) {
            Text(Markdown.parse(content: artifacts.content))
                .font(eventviewsize_to_font(size))

            if show_images && artifacts.images.count > 0 {
                ImageCarousel(urls: artifacts.images)
            }
            if artifacts.invoices.count > 0 {
                InvoicesView(invoices: artifacts.invoices)
                    .frame(width: 200)
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
        let content = "hi there https://jb55.com/s/Oct12-150217.png 5739a762ef6124dd.jpg"
        let artifacts = NoteArtifacts(content: content, images: [], invoices: [])
        NoteContentView(privkey: "", event: NostrEvent(content: content, pubkey: "pk"), profiles: state.profiles, show_images: true, artifacts: artifacts, size: .normal)
    }
}
