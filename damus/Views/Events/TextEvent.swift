//
//  TextEvent.swift
//  damus
//
//  Created by William Casarin on 2023-02-03.
//

import SwiftUI

struct TextEvent: View {
    let damus: DamusState
    let event: NostrEvent
    let pubkey: String
    let has_action_bar: Bool
    let booster_pubkey: String?
    
    var body: some View {
        HStack(alignment: .top) {
            let profile = damus.profiles.lookup(id: pubkey)
        
            let is_anon = event_is_anonymous(ev: event)
            VStack {
                MaybeAnonPfpView(state: damus, is_anon: is_anon, pubkey: pubkey)
                
                Spacer()
            }

            VStack(alignment: .leading) {
                HStack(alignment: .center) {
                    let pk = is_anon ? "anon" : pubkey
                    EventProfileName(pubkey: pk, profile: profile, damus: damus, show_friend_confirmed: true, size: .normal)
                    
                    Text(verbatim: "\(format_relative_time(event.created_at))")
                        .foregroundColor(.gray)
                    
                    Spacer()
                }
                
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
        .event_context_menu(event, keypair: damus.keypair, target_pubkey: pubkey)
    }
}

struct TextEvent_Previews: PreviewProvider {
    static var previews: some View {
        TextEvent(damus: test_damus_state(), event: test_event, pubkey: "pk", has_action_bar: true, booster_pubkey: nil)
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
