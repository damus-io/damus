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
        HStack(alignment: .top) {
            let profile = damus.profiles.lookup(id: pubkey)
        
            let is_anon = event_is_anonymous(ev: event)
            VStack {
                MaybeAnonPfpView(state: damus, is_anon: is_anon, pubkey: pubkey)
                
                Spacer()
            }

            VStack(alignment: .leading) {
                HStack(alignment: .center, spacing: 0) {
                    let pk = is_anon ? "anon" : pubkey
                    EventProfileName(pubkey: pk, profile: profile, damus: damus, show_friend_confirmed: true, size: .normal)
                    
                    Text(verbatim: "⋅")
                        .font(.footnote)
                        .foregroundColor(.gray)
                    Text(verbatim: "\(format_relative_time(event.created_at))")
                        .font(.system(size: 16))
                        .foregroundColor(.gray)
                    
                    Spacer()
                    
                    EventMenuContext(event: event, keypair: damus.keypair, target_pubkey: event.pubkey, bookmarks: damus.bookmarks)
                        .padding([.bottom], 4)

                }
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                
                EventBody(damus_state: damus, event: event, size: .normal)
                
                if let mention = first_eref_mention(ev: event, privkey: damus.keypair.privkey) {
                    BuilderEventView(damus: damus, event_id: mention.ref.id)
                }
                
                if has_action_bar {
                    Rectangle().frame(height: 2).opacity(0)
                    
                    EventActionBar(damus_state: damus, event: event)
                        .padding([.top], 4)
                }
            }
            .padding([.leading], 2)
        }
        .contentShape(Rectangle())
        .background(event_validity_color(event.validity))
        .id(event.id)
        .frame(maxWidth: .infinity, minHeight: PFP_SIZE)
        .padding([.bottom], 2)
    }
}

struct TextEvent_Previews: PreviewProvider {
    static var previews: some View {
        TextEvent(damus: test_damus_state(), event: test_event, pubkey: "pk", options: [])
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
