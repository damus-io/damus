//
//  NoteContentView.swift
//  damus
//
//  Created by William Casarin on 2022-05-04.
//

import SwiftUI


func render_note_content(ev: NostrEvent, profiles: Profiles, privkey: String?) -> String {
    let blocks = ev.blocks(privkey)
    return blocks.reduce("") { str, block in
        switch block {
        case .mention(let m):
            return str + mention_str(m, profiles: profiles)
        case .text(let txt):
            return str + txt
        case .hashtag(let htag):
            return str + hashtag_str(htag)
        }
    }
}

struct NoteContentView: View {
    let privkey: String?
    let event: NostrEvent
    let profiles: Profiles
    
    @State var content: String
    
    func MainContent() -> some View {
        let md_opts: AttributedString.MarkdownParsingOptions =
            .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        
        guard var txt = try? AttributedString(markdown: content, options: md_opts) else {
            return Text(content)
        }
        
        return Text(txt)
    }
    
    var body: some View {
        MainContent()
            .onAppear() {
                self.content = render_note_content(ev: event, profiles: profiles, privkey: privkey)
            }
            .onReceive(handle_notify(.profile_updated)) { notif in
                let profile = notif.object as! ProfileUpdate
                let blocks = event.blocks(privkey)
                for block in blocks {
                    switch block {
                    case .mention(let m):
                        if m.type == .pubkey && m.ref.ref_id == profile.pubkey {
                            content = render_note_content(ev: event, profiles: profiles, privkey: privkey)
                        }
                    case .text: return
                    case .hashtag: return
                    }
                }
            }
    }
}

func hashtag_str(_ htag: String) -> String {
    return "[#\(htag)](nostr:hashtag:\(htag))"
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


/*
struct NoteContentView_Previews: PreviewProvider {
    static var previews: some View {
        NoteContentView()
    }
}
 */
