//
//  NoteContentView.swift
//  damus
//
//  Created by William Casarin on 2022-05-04.
//

import SwiftUI

func NoteContentView(_ ev: NostrEvent) -> some View {
    let txt = parse_mentions(content: ev.content, tags: ev.tags)
        .reduce("") { str, block in
            switch block {
            case .mention(let m):
                return str + mention_str(m)
            case .text(let txt):
                return str + txt
            }
        }
    
    let md_opts: AttributedString.MarkdownParsingOptions =
        .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    
    guard let txt = try? AttributedString(markdown: txt, options: md_opts) else {
        return Text(ev.content)
    }
    
    return Text(txt)
}

func mention_str(_ m: Mention) -> String {
    switch m.type {
    case .pubkey:
        let pk = m.ref.ref_id
        return "[@\(abbrev_pubkey(pk))](nostr:\(encode_pubkey(m.ref)))"
    case .event:
        let evid = m.ref.ref_id
        return "[*\(abbrev_pubkey(evid))](nostr:\(encode_event_id(m.ref)))"
    }
}

// TODO: bech32 and relay hints
func encode_event_id(_ ref: ReferencedId) -> String {
    return "e_" + ref.ref_id
}

func encode_pubkey(_ ref: ReferencedId) -> String {
    return "p_" + ref.ref_id
}

/*
struct NoteContentView_Previews: PreviewProvider {
    static var previews: some View {
        NoteContentView()
    }
}
 */
