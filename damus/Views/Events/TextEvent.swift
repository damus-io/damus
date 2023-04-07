//
//  TextEvent.swift
//  damus
//
//  Created by William Casarin on 2023-02-03.
//

import SwiftUI

struct EventViewOptions: OptionSet {
    let rawValue: UInt8
    static let no_action_bar = EventViewOptions(rawValue: 1 << 0)
    static let no_replying_to = EventViewOptions(rawValue: 1 << 1)
    static let no_images = EventViewOptions(rawValue: 1 << 2)
    static let wide = EventViewOptions(rawValue: 1 << 3)
    static let truncate_content = EventViewOptions(rawValue: 1 << 4)
    static let pad_content = EventViewOptions(rawValue: 1 << 5)
    static let no_translate = EventViewOptions(rawValue: 1 << 6)
}

struct TextEvent: View {
    let damus: DamusState
    let event: NostrEvent
    let pubkey: String
    let options: EventViewOptions
    
    var has_action_bar: Bool {
        !options.contains(.no_action_bar)
    }
    
    var body: some View {
        Group {
            if options.contains(.wide) {
                WideStyle
            } else {
                ThreadedStyle
            }
        }
        .contentShape(Rectangle())
        .background(event_validity_color(event.validity))
        .id(event.id)
        .frame(maxWidth: .infinity, minHeight: PFP_SIZE)
        .padding([.bottom], 2)
    }
    
    func Pfp(is_anon: Bool) -> some View {
        MaybeAnonPfpView(state: damus, is_anon: is_anon, pubkey: pubkey)
    }
    
    func TopPart(is_anon: Bool) -> some View {
        HStack(alignment: .center, spacing: 0) {
            ProfileName(is_anon: is_anon)
            TimeDot
            Time
            Spacer()
            ContextButton
        }
        .lineLimit(1)
    }
    
    var ReplyPart: some View {
        Group {
            if event_is_reply(event, privkey: damus.keypair.privkey) {
                ReplyDescription(event: event, profiles: damus.profiles)
            } else {
                EmptyView()
            }
        }
    }
    
    var WideStyle: some View {
        VStack(alignment: .leading) {
            let is_anon = event_is_anonymous(ev: event)
            
            HStack(spacing: 10) {
                Pfp(is_anon: is_anon)
                VStack {
                    TopPart(is_anon: is_anon)
                    ReplyPart
                }
            }
            .padding(.horizontal)

            EvBody(options: self.options.union(.pad_content))
            
            if let mention = first_eref_mention(ev: event, privkey: damus.keypair.privkey) {
                Mention(mention)
                    .padding(.horizontal)
            }
            
            if has_action_bar {
                //EmptyRect
                ActionBar
                    .padding(.horizontal)
            }
        }
    }
    
    var TimeDot: some View {
        Text(verbatim: "⋅")
            .font(.footnote)
            .foregroundColor(.gray)
    }
    
    var Time: some View {
        Text(verbatim: "\(format_relative_time(event.created_at))")
            .font(.system(size: 16))
            .foregroundColor(.gray)
    }
    
    var ContextButton: some View {
        EventMenuContext(event: event, keypair: damus.keypair, target_pubkey: event.pubkey, bookmarks: damus.bookmarks)
            .padding([.bottom], 4)
    }
    
    func ProfileName(is_anon: Bool) -> some View {
        let profile = damus.profiles.lookup(id: pubkey)
        let pk = is_anon ? "anon" : pubkey
        return EventProfileName(pubkey: pk, profile: profile, damus: damus, show_friend_confirmed: true, size: .normal)
    }
    
    func EvBody(options: EventViewOptions) -> some View {
        return EventBody(damus_state: damus, event: event, size: .normal, options: options)
    }
    
    func Mention(_ mention: Mention) -> some View {
        return BuilderEventView(damus: damus, event_id: mention.ref.id)
    }
    
    var ActionBar: some View {
        return EventActionBar(damus_state: damus, event: event)
            .padding([.top], 4)
    }
    
    var EmptyRect: some View {
        return Rectangle().frame(height: 2).opacity(0)
    }
    
    var ThreadedStyle: some View {
        HStack(alignment: .top) {
        
            let is_anon = event_is_anonymous(ev: event)
            VStack {
                Pfp(is_anon: is_anon)
                
                Spacer()
            }

            VStack(alignment: .leading) {
                TopPart(is_anon: is_anon)
                
                ReplyPart
                EvBody(options: self.options)
                
                if let mention = first_eref_mention(ev: event, privkey: damus.keypair.privkey) {
                    Mention(mention)
                }
                
                if has_action_bar {
                    EmptyRect
                    ActionBar
                }
            }
            .padding([.leading], 2)
        }
    }
}

func event_has_tag(ev: NostrEvent, tag: String) -> Bool {
    for t in ev.tags {
        if t.count >= 1 && t[0] == tag {
            return true
        }
    }
    
    return false
}


func event_is_anonymous(ev: NostrEvent) -> Bool {
    return ev.known_kind == .zap_request && event_has_tag(ev: ev, tag: "anon")
}

struct TextEvent_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            TextEvent(damus: test_damus_state(), event: test_event, pubkey: "pk", options: [])
                .frame(height: 400)
            
            TextEvent(damus: test_damus_state(), event: test_event, pubkey: "pk", options: [.wide])
                .frame(height: 400)
        }
    }
}

