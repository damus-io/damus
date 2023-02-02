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

            VStack {
                let pmodel = ProfileModel(pubkey: pubkey, damus: damus)
                let pv = ProfileView(damus_state: damus, profile: pmodel, followers: FollowersModel(damus_state: damus, target: pubkey))
                
                NavigationLink(destination: pv) {
                    ProfilePicView(pubkey: pubkey, size: PFP_SIZE, highlight: .none, profiles: damus.profiles, contacts: damus.contacts)
                }
                
                Spacer()
            }

            VStack(alignment: .leading) {
                HStack(alignment: .center) {
                    EventProfileName(pubkey: pubkey, profile: profile, damus: damus, show_friend_confirmed: true, size: .normal)
                    
                    Text("\(format_relative_time(event.created_at))")
                        .foregroundColor(.gray)
                    
                    Spacer()
                }
                
                EventBody(damus_state: damus, event: event, size: .normal)
                
                if let mention = first_eref_mention(ev: event, privkey: damus.keypair.privkey) {
                    BuilderEventView(damus: damus, event_id: mention.ref.id)
                }
                
                if has_action_bar {
                    Rectangle().frame(height: 2).opacity(0)
                    
                    let bar = make_actionbar_model(ev: event, damus: damus)
                    
                    EventActionBar(damus_state: damus, event: event, bar: bar)
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
