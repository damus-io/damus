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
    let size: EventViewKind
    
    var pubkey: String {
        event.pubkey
    }
    
    @StateObject var bar: ActionBarModel
    
    init(damus: DamusState, event: NostrEvent, size: EventViewKind) {
        self.damus = damus
        self.event = event
        self.size = size
        self._bar = StateObject(wrappedValue: make_actionbar_model(ev: event.id, damus: damus))
    }
    
    var body: some View {
        HStack(alignment: .top) {
            let profile = damus.profiles.lookup(id: pubkey)

            VStack(alignment: .leading) {
                HStack {
                    EventProfile(damus_state: damus, pubkey: pubkey, profile: profile, size: .normal)
                    
                    Spacer()
                    
                    EventMenuContext(event: event, keypair: damus.keypair, target_pubkey: event.pubkey, bookmarks: damus.bookmarks)
                        .padding([.bottom], 4)

                }
                .padding(.horizontal)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                
                if event_is_reply(event, privkey: damus.keypair.privkey) {
                    ReplyDescription(event: event, profiles: damus.profiles)
                        .padding(.horizontal)
                }
                
                EventBody(damus_state: damus, event: event, size: size, options: [.pad_content])
                
                if let mention = first_eref_mention(ev: event, privkey: damus.keypair.privkey) {
                    BuilderEventView(damus: damus, event_id: mention.ref.id)
                        .padding(.horizontal)
                }
                
                Text(verbatim: "\(format_date(event.created_at))")
                    .padding([.top, .leading, .trailing])
                    .font(.footnote)
                    .foregroundColor(.gray)
                
                Divider()
                    .padding([.bottom], 4)
                
                if !bar.is_empty {
                    EventDetailBar(state: damus, target: event.id, target_pk: event.pubkey)
                        .padding(.horizontal)
                    Divider()
                }
                
                EventActionBar(damus_state: damus, event: event)
                    .padding([.top], 4)
                    .padding(.horizontal)

                Divider()
                    .padding([.top], 4)
            }
            .onReceive(handle_notify(.update_stats)) { n in
                let target = n.object as! String
                guard target == self.event.id else { return }
                self.bar.update(damus: self.damus, evid: target)
            }
            .compositingGroup()
        }
    }
}

struct SelectedEventView_Previews: PreviewProvider {
    static var previews: some View {
        SelectedEventView(damus: test_damus_state(), event: test_event, size: .selected)
            .padding()
    }
}
