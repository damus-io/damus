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
    
    var pubkey: Pubkey {
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
            VStack(alignment: .leading) {
                HStack {
                    EventProfile(damus_state: damus, pubkey: pubkey, size: .normal)
                    
                    Spacer()
                    
                    EventMenuContext(damus: damus, event: event)
                        .padding([.bottom], 4)
                }
                .padding(.horizontal)
                .minimumScaleFactor(0.75)
                .lineLimit(1)
                
                ReplyPart(events: damus.events, event: event, keypair: damus.keypair, ndb: damus.ndb)
                    .padding(.horizontal)
                
                ProxyView(event: event)
                    .padding(.top, 5)
                    .padding(.horizontal)

                EventBody(damus_state: damus, event: event, size: size, options: [.wide])

                Mention
                
                Text(verbatim: "\(format_date(created_at: event.created_at))")
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
            .onReceive(handle_notify(.update_stats)) { target in
                guard target == self.event.id else { return }
                self.bar.update(damus: self.damus, evid: target)
            }
            .compositingGroup()
        }
    }
    
    var Mention: some View {
        Group {
            if let mention = first_eref_mention(ndb: damus.ndb, ev: event, keypair: damus.keypair) {
                MentionView(damus_state: damus, mention: mention)
                    .padding(.horizontal)
            }
        }
    }
}

struct SelectedEventView_Previews: PreviewProvider {
    static var previews: some View {
        SelectedEventView(damus: test_damus_state, event: test_note, size: .selected)
    }
}
