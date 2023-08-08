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
    let isLastInGroup: Bool

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
        var options: EventViewOptions = [.only_text]
        
        if !self.damus_state.settings.translate_dms {
            options.insert(.no_translate)
        }
        
        return options
    }
    
    func format_timestamp(timestamp: UInt32) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "h:mm a"
        let date = Date(timeIntervalSince1970: TimeInterval(timestamp))
        return dateFormatter.string(from: date)
    }
    
    let LINEAR_GRADIENT_DM = LinearGradient(gradient: Gradient(colors: [
        DamusColors.purple,
        .pink
    ]), startPoint: .topTrailing, endPoint: .bottomTrailing)
    
    func DM(content: CompatibleText, isLastInDM: Bool) -> some View {
        return Group {
            HStack {
                if is_ours {
                    Spacer(minLength: UIScreen.main.bounds.width * 0.1)
                }

                let should_show_img = should_show_images(settings: damus_state.settings, contacts: damus_state.contacts, ev: event, our_pubkey: damus_state.pubkey)

                NoteContentView(damus_state: damus_state, event: event, show_images: should_show_img, size: .normal, options: dm_options)
                    .frame(minWidth: 30)
                    .contentShape(Rectangle())
                    .padding(.horizontal, 12.5)
                    .padding(.vertical, 9)
                    .foregroundColor(.primary)
                    .background(
                        Group {
                            if is_ours {
                                LINEAR_GRADIENT_DM.opacity(0.75)
                            } else {
                                Color.secondary.opacity(0.15)
                            }
                        }
                    )
                    .background(VisualEffectView(effect: UIBlurEffect(style: .prominent)))
                    .clipShape(ChatBubbleShape(direction: (isLastInGroup && isLastInDM) ? (is_ours ? ChatBubbleShape.Direction.right: ChatBubbleShape.Direction.left): ChatBubbleShape.Direction.none))
                    .contextMenu{MenuItems(event: event, keypair: damus_state.keypair, target_pubkey: event.pubkey, bookmarks: damus_state.bookmarks, muted_threads: damus_state.muted_threads, settings: damus_state.settings)}

                if !is_ours {
                    Spacer(minLength: UIScreen.main.bounds.width * 0.1)
                }
            }
        }
    }

    func Mention(mention: Mention<NoteId>) -> some View {
        Group {
            HStack {
                if is_ours {
                    Spacer(minLength: UIScreen.main.bounds.width * 0.1)
                }

                BuilderEventView(damus: damus_state, event_id: mention.ref)
                    .contextMenu{MenuItems(event: event, keypair: damus_state.keypair, target_pubkey: event.pubkey, bookmarks: damus_state.bookmarks, muted_threads: damus_state.muted_threads, settings: damus_state.settings)}

                if !is_ours {
                    Spacer(minLength: UIScreen.main.bounds.width * 0.1)
                }
            }
        }
    }

    @MainActor
    func Image(urls: [MediaUrl], isLastInDM: Bool) -> some View {
        return Group {
            HStack {
                if is_ours {
                    Spacer(minLength: UIScreen.main.bounds.width * 0.1)
                }
                
                let should_show_img = should_show_images(settings: damus_state.settings, contacts: damus_state.contacts, ev: event, our_pubkey: damus_state.pubkey)
                if should_show_img {
                    ImageCarousel(state: damus_state, evid: event.id, urls: urls)
                        .clipShape(ChatBubbleShape(direction: (isLastInGroup && isLastInDM) ? (is_ours ? ChatBubbleShape.Direction.right: ChatBubbleShape.Direction.left): ChatBubbleShape.Direction.none))
                        .contextMenu{MenuItems(event: event, keypair: damus_state.keypair, target_pubkey: event.pubkey, bookmarks: damus_state.bookmarks, muted_threads: damus_state.muted_threads, settings: damus_state.settings)}
                } else if !should_show_img {
                    ZStack {
                        ImageCarousel(state: damus_state, evid: event.id, urls: urls)
                        Blur()
                            .disabled(true)
                    }
                    .clipShape(ChatBubbleShape(direction: (isLastInGroup && isLastInDM) ? (is_ours ? ChatBubbleShape.Direction.right: ChatBubbleShape.Direction.left): ChatBubbleShape.Direction.none))
                    .contextMenu{MenuItems(event: event, keypair: damus_state.keypair, target_pubkey: event.pubkey, bookmarks: damus_state.bookmarks, muted_threads: damus_state.muted_threads, settings: damus_state.settings)}
                }
                
                if !is_ours {
                    Spacer(minLength: UIScreen.main.bounds.width * 0.1)
                }
            }
        }
    }

    func Invoice(invoices: [Invoice], isLastInDM: Bool) -> some View {
        return Group {
            HStack {
                if is_ours {
                    Spacer(minLength: UIScreen.main.bounds.width * 0.1)
                }

                InvoicesView(our_pubkey: damus_state.keypair.pubkey, invoices: invoices, settings: damus_state.settings)
                    .clipShape(ChatBubbleShape(direction: (isLastInGroup && isLastInDM) ? (is_ours ? ChatBubbleShape.Direction.right: ChatBubbleShape.Direction.left): ChatBubbleShape.Direction.none))
                    .contextMenu{MenuItems(event: event, keypair: damus_state.keypair, target_pubkey: event.pubkey, bookmarks: damus_state.bookmarks, muted_threads: damus_state.muted_threads, settings: damus_state.settings)}
                
                if !is_ours {
                    Spacer(minLength: UIScreen.main.bounds.width * 0.1)
                }
            }
        }
    }

    func TimeStamp() -> some View {
        return Group {
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
                var trimmed = txt
                if let prev = blocks[safe: ind-1], case .url(let u) = prev, classify_url(u).is_media != nil {
                    trimmed = " " + trim_prefix(trimmed)
                }
                
                if let next = blocks[safe: ind+1] {
                    if case .url(let u) = next, classify_url(u).is_media != nil {
                        trimmed = trim_suffix(trimmed)
                    } else if case .mention(let m) = next, case .note = m.ref, one_note_ref {
                        trimmed = trim_suffix(trimmed)
                    }
                }
                if (!trimmed.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) {
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
                if !(classify_url(url).is_media != nil) {
                    show_text = true
                    return str + url_str(url)
                } else {
                    return str
                }
            }
        }
        
        return (show_text, txt)
    }
    
    func getLastInDM(text: CompatibleText?, mention: Mention<NoteId>?, url: [MediaUrl]?, invoices: [Invoice]?) -> DMContentType? {
        var last: DMContentType?
        if let text {
            last = .text
        }
        if let mention {
            last = .mention
        }
        if let url {
            last = .url
        }
        if let invoices {
            last = .invoice
        }
        return last
    }

    var body: some View {
        VStack {
            let (show_text, filtered_content): (Bool, CompatibleText?) = filter_content(blocks: event.blocks(damus_state.keypair.privkey), profiles: damus_state.profiles, privkey: damus_state.keypair.privkey)
            let mention = first_eref_mention(ev: event, privkey: damus_state.keypair.privkey)
            let url = separate_images(ev: event, privkey: damus_state.keypair.privkey)
            let invoices = separate_invoices(ev: event, privkey: damus_state.keypair.privkey)
            let lastInDM = getLastInDM(text: filtered_content, mention: mention, url: url, invoices: invoices)
            
            if show_text, let filtered_content = filtered_content {
                DM(content: filtered_content, isLastInDM: lastInDM == .text).padding(.bottom, (isLastInGroup && lastInDM == .text)  ? 0 : -6)
            }
            if let mention {
                Mention(mention: mention).padding(.bottom, (isLastInGroup && lastInDM == .mention) ? 0 : -6)
            }
            if let url {
                Image(urls: url, isLastInDM: lastInDM == .url).padding(.bottom, (isLastInGroup && lastInDM == .url) ? 0 : -6)
            }
            if let invoices {
                Invoice(invoices: invoices, isLastInDM: lastInDM == .invoice).padding(.bottom, (isLastInGroup && lastInDM == .invoice) ? 0 : -6)
            }
            if (isLastInGroup) {
                TimeStamp().padding(.top, -5)
            }
        }
    }
}

enum DMContentType {
    case text
    case mention
    case url
    case invoice
}

struct ChatBubbleShape: Shape {
    enum Direction {
        case left
        case right
        case none
    }
    
    let direction: Direction
    
    func path(in rect: CGRect) -> Path {
        return (direction == .none) ? getBubblePath(in: rect) : ( (direction == .left) ? getLeftBubblePath(in: rect) : getRightBubblePath(in: rect) )
    }
    
    private func getBubblePath(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let cornerRadius: CGFloat = 17
        let path = Path { p in
            p.move(to: CGPoint(x: cornerRadius, y: height))
            p.addLine(to: CGPoint(x: width - cornerRadius, y: height))
            p.addCurve(to: CGPoint(x: width, y: height - cornerRadius),
                       control1: CGPoint(x: width - cornerRadius/2, y: height),
                       control2: CGPoint(x: width, y: height - cornerRadius/2))
            p.addLine(to: CGPoint(x: width, y: cornerRadius))
            p.addCurve(to: CGPoint(x: width - cornerRadius, y: 0),
                       control1: CGPoint(x: width, y: cornerRadius/2),
                       control2: CGPoint(x: width - cornerRadius/2, y: 0))
            p.addLine(to: CGPoint(x: cornerRadius, y: 0))
            p.addCurve(to: CGPoint(x: 0, y: cornerRadius),
                       control1: CGPoint(x: cornerRadius/2, y: 0),
                       control2: CGPoint(x: 0, y: cornerRadius/2))
            p.addLine(to: CGPoint(x: 0, y: height - cornerRadius))
            p.addCurve(to: CGPoint(x: cornerRadius, y: height),
                       control1: CGPoint(x: 0, y: height - cornerRadius/2),
                       control2: CGPoint(x: cornerRadius/2, y: height))
        }
        return path
    }
    
    private func getLeftBubblePath(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let path = Path { p in
            p.move(to: CGPoint(x: 25, y: height))
            p.addLine(to: CGPoint(x: width - 20, y: height))
            p.addCurve(to: CGPoint(x: width, y: height - 20),
                       control1: CGPoint(x: width - 8, y: height),
                       control2: CGPoint(x: width, y: height - 8))
            p.addLine(to: CGPoint(x: width, y: 20))
            p.addCurve(to: CGPoint(x: width - 20, y: 0),
                       control1: CGPoint(x: width, y: 8),
                       control2: CGPoint(x: width - 8, y: 0))
            p.addLine(to: CGPoint(x: 21, y: 0))
            p.addCurve(to: CGPoint(x: 4, y: 20),
                       control1: CGPoint(x: 12, y: 0),
                       control2: CGPoint(x: 4, y: 8))
            p.addLine(to: CGPoint(x: 4, y: height - 11))
            p.addCurve(to: CGPoint(x: 0, y: height),
                       control1: CGPoint(x: 4, y: height - 1),
                       control2: CGPoint(x: 0, y: height))
            p.addLine(to: CGPoint(x: -0.05, y: height - 0.01))
            p.addCurve(to: CGPoint(x: 11.0, y: height - 4.0),
                       control1: CGPoint(x: 4.0, y: height + 0.5),
                       control2: CGPoint(x: 8, y: height - 1))
            p.addCurve(to: CGPoint(x: 25, y: height),
                       control1: CGPoint(x: 16, y: height),
                       control2: CGPoint(x: 20, y: height))
            
        }
        return path
    }
    
    private func getRightBubblePath(in rect: CGRect) -> Path {
        let width = rect.width
        let height = rect.height
        let path = Path { p in
            p.move(to: CGPoint(x: 25, y: height))
            p.addLine(to: CGPoint(x:  20, y: height))
            p.addCurve(to: CGPoint(x: 0, y: height - 20),
                       control1: CGPoint(x: 8, y: height),
                       control2: CGPoint(x: 0, y: height - 8))
            p.addLine(to: CGPoint(x: 0, y: 20))
            p.addCurve(to: CGPoint(x: 20, y: 0),
                       control1: CGPoint(x: 0, y: 8),
                       control2: CGPoint(x: 8, y: 0))
            p.addLine(to: CGPoint(x: width - 21, y: 0))
            p.addCurve(to: CGPoint(x: width - 4, y: 20),
                       control1: CGPoint(x: width - 12, y: 0),
                       control2: CGPoint(x: width - 4, y: 8))
            p.addLine(to: CGPoint(x: width - 4, y: height - 11))
            p.addCurve(to: CGPoint(x: width, y: height),
                       control1: CGPoint(x: width - 4, y: height - 1),
                       control2: CGPoint(x: width, y: height))
            p.addLine(to: CGPoint(x: width + 0.05, y: height - 0.01))
            p.addCurve(to: CGPoint(x: width - 11, y: height - 4),
                       control1: CGPoint(x: width - 4, y: height + 0.5),
                       control2: CGPoint(x: width - 8, y: height - 1))
            p.addCurve(to: CGPoint(x: width - 25, y: height),
                       control1: CGPoint(x: width - 16, y: height),
                       control2: CGPoint(x: width - 20, y: height))
        }
        return path
    }
}

struct DMView_Previews: PreviewProvider {
    static var previews: some View {
        let ev = NostrEvent(content: "Hey there *buddy*, want to grab some drinks later? 🍻", keypair: test_keypair, kind: 1, tags: [])!
        DMView(event: ev, damus_state: test_damus_state(), isLastInGroup: false)
    }
}
