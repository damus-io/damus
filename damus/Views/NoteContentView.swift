//
//  NoteContentView.swift
//  damus
//
//  Created by William Casarin on 2022-05-04.
//

import SwiftUI


func render_note_content(ev: NostrEvent, profiles: Profiles, privkey: String?) -> (String, [URL]) {
    let blocks = ev.blocks(privkey)
    var img_urls: [URL] = []
    let txt = blocks.reduce("") { str, block in
        switch block {
        case .mention(let m):
            return str + mention_str(m, profiles: profiles)
        case .text(let txt):
            return str + txt
        case .hashtag(let htag):
            return str + hashtag_str(htag)
        case .url(let url):
            if is_image_url(url) {
                img_urls.append(url)
            }
            return str + url.absoluteString
        }
    }
    
    return (txt, img_urls)
}

func is_image_url(_ url: URL) -> Bool {
    let str = url.lastPathComponent
    return str.hasSuffix("png") || str.hasSuffix("jpg") || str.hasSuffix("jpeg")
}

struct NoteContentView: View {
    let privkey: String?
    let event: NostrEvent
    let profiles: Profiles
    
    let show_images: Bool
    
    @State var content: String
    @State var images: [URL] = []
    
    func MainContent() -> some View {
        let md_opts: AttributedString.MarkdownParsingOptions =
            .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        
        return VStack(alignment: .leading) {
            if let txt = try? AttributedString(markdown: content, options: md_opts) {
                Text(txt)
            } else {
                Text(content)
            }
            if show_images && images.count > 0 {
                ImageCarousel(urls: images)
            }
        }
    }
    
    var body: some View {
        MainContent()
            .onAppear() {
                let (txt, images) = render_note_content(ev: event, profiles: profiles, privkey: privkey)
                self.content = txt
                self.images = images
            }
            .onReceive(handle_notify(.profile_updated)) { notif in
                let profile = notif.object as! ProfileUpdate
                let blocks = event.blocks(privkey)
                for block in blocks {
                    switch block {
                    case .mention(let m):
                        if m.type == .pubkey && m.ref.ref_id == profile.pubkey {
                            let (txt, images) = render_note_content(ev: event, profiles: profiles, privkey: privkey)
                            self.content = txt
                            self.images = images
                        }
                    case .text: return
                    case .hashtag: return
                    case .url: return
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
        let evid = m.ref.ref_id
        return "[&\(abbrev_pubkey(evid))](nostr:\(encode_event_id_uri(m.ref)))"
    }
}


struct NoteContentView_Previews: PreviewProvider {
    static var previews: some View {
        let state = test_damus_state()
        let content = "hi there https://jb55.com/s/Oct12-150217.png 5739a762ef6124dd.jpg"
        NoteContentView(privkey: "", event: NostrEvent(content: content, pubkey: "pk"), profiles: state.profiles, show_images: true, content: content)
    }
}
