//
//  SelectedEventView.swift
//  damus
//
//  Created by William Casarin on 2023-01-23.
//

import SwiftUI

struct SelectedEventView: View {
    let damus: DamusState
    let event: NostrEvent
    
    var pubkey: String {
        event.pubkey
    }
    
    @StateObject var bar: ActionBarModel
    
    init(damus: DamusState, event: NostrEvent) {
        self.damus = damus
        self.event = event
        self._bar = StateObject(wrappedValue: make_actionbar_model(ev: event.id, damus: damus))
    }
    
    var body: some View {
        HStack(alignment: .top) {
            let profile = damus.profiles.lookup(id: pubkey)

            VStack(alignment: .leading) {
                EventProfile(damus_state: damus, pubkey: pubkey, profile: profile, size: .normal)
                EventBody(damus_state: damus, event: event, size: .selected)
                
                if let mention = first_eref_mention(ev: event, privkey: damus.keypair.privkey) {
                    BuilderEventView(damus: damus, event_id: mention.ref.id)
                }
                
                Text("\(format_date(event.created_at))")
                    .padding(.top, 10)
                    .font(.footnote)
                    .foregroundColor(.gray)
                
                Divider()
                    .padding([.bottom], 4)
                
                if !bar.is_empty {
                    EventDetailBar(state: damus, target: event.id, target_pk: event.pubkey)
                    Divider()
                }
                
                EventActionBar(damus_state: damus, event: event)
                    .padding([.top], 4)

                Divider()
                    .padding([.top], 4)
            }
            .onReceive(handle_notify(.update_stats)) { n in
                let target = n.object as! String
                guard target == self.event.id else { return }
                self.bar.update(damus: self.damus, evid: target)
            }
            .padding([.leading], 2)
            .event_context_menu(event, keypair: damus.keypair, target_pubkey: event.pubkey)
        }
    }
}

struct SelectedEventView_Previews: PreviewProvider {
    static var previews: some View {
        SelectedEventView(damus: test_damus_state(), event: test_event)
            .padding()
    }
}
