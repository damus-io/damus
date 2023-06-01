//
//  DMView.swift
//  damus
//
//  Created by William Casarin on 2022-07-01.
//

import SwiftUI

struct DMView: View {
    let event: NostrEvent
    let damus_state: DamusState

    var is_ours: Bool {
        event.pubkey == damus_state.pubkey
    }
    
    var Mention: some View {
        Group {
            if let mention = first_eref_mention(ev: event, privkey: damus_state.keypair.privkey) {
                BuilderEventView(damus: damus_state, event_id: mention.ref)
            } else {
                EmptyView()
            }
        }
    }
    
    var dm_options: EventViewOptions {
        if self.damus_state.settings.translate_dms {
            return []
        }
        
        return [.no_translate]
    }
    
    func format_timestamp(timestamp: UInt32) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "h:mm a"
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return dateFormatter.string(from: date)
    }

    var DM: some View {
        HStack {
            if is_ours {
                Spacer(minLength: UIScreen.main.bounds.width * 0.2)
            }

            let should_show_img = should_show_images(settings: damus_state.settings, contacts: damus_state.contacts, ev: event, our_pubkey: damus_state.pubkey)

            VStack(alignment: .trailing) {
                NoteContentView(damus_state: damus_state, event: event, show_images: should_show_img, size: .normal, options: dm_options)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding([.top, .leading, .trailing], 10)
                    .padding([.bottom], 25)
                    .background(VisualEffectView(effect: UIBlurEffect(style: .prominent))
                        .background(is_ours ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.15))
                    )
                    .cornerRadius(8.0)
                    .tint(is_ours ? Color.white : Color.accentColor)

                Text(format_relative_time(event.created_at))
                   .font(.footnote)
                   .foregroundColor(.gray)
                   .opacity(0.8)
            }

            if !is_ours {
                Spacer(minLength: UIScreen.main.bounds.width * 0.2)
            }
        }
    }

    var TimeStamp: some View {
        Group {
            HStack {
                if is_ours {
                    Spacer(minLength: UIScreen.main.bounds.width * 0.1)
                }

                Text(format_timestamp(timestamp: event.created_at))
                    .font(.system(size: 11))
                    .font(.footnote)
                    .foregroundColor(.gray)
                
                if !is_ours {
                    Spacer(minLength: UIScreen.main.bounds.width * 0.1)
                }
            }
        }
    }

    func filter_content(blocks bs: Blocks, profiles: Profiles, privkey: Privkey?) -> (Bool, CompatibleText?) {
        let blocks = bs.blocks
        
        let one_note_ref = blocks
            .filter({ $0.is_note_mention })
            .count == 1
        
        var ind: Int = -1
        var show_text: Bool = false
        let txt: CompatibleText = blocks.reduce(CompatibleText()) { str, block in
            ind = ind + 1
            
            switch block {
            case .mention(let m):
                if case .note = m.ref, one_note_ref {
                    return str
                }
                if case .pubkey(_) = m.ref {
                    show_text = true
                }
                return str + mention_str(m, profiles: profiles)
            case .text(let txt):
                let trimmed = reduce_text_block(blocks: blocks, ind: ind, txt: txt, one_note_ref: one_note_ref)
                if !trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    show_text = true
                }
                return str + CompatibleText(stringLiteral: trimmed)
            case .relay(let relay):
                show_text = true
                return str + CompatibleText(stringLiteral: relay)
            case .hashtag(let htag):
                show_text = true
                return str + hashtag_str(htag)
            case .invoice:
                return str
            case .url(let url):
                if classify_url(url).is_media == nil {
                    show_text = true
                    return str + url_str(url)
                } else {
                    return str
                }
            }
        }

        return (show_text, txt)
    }

    var body: some View {
        VStack {
            Mention
            DM
        }
        
    }
}

struct DMView_Previews: PreviewProvider {
    static var previews: some View {
        let ev = NostrEvent(content: "Hey there *buddy*, want to grab some drinks later? 🍻", keypair: test_keypair, kind: 1, tags: [])!
        DMView(event: ev, damus_state: test_damus_state())
    }
}
