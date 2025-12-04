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
    
    @State private var relays: [RelayURL] = []
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
                
                // Keep relay count aligned with timestamp while staying tappable for relay details.
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "\(format_date(created_at: event.created_at))")
                        .font(.footnote)
                        .foregroundColor(.gray)

                    Spacer(minLength: 8)

                    if !relays.isEmpty {
                        NavigationLink(value: Route.UserRelays(relays: relays)) {
                            let nounString = pluralizedString(key: "relays_count", count: relays.count)
                            HStack(spacing: 4) {
                                Text(verbatim: relays.count.formatted())
                                    .font(.footnote.weight(.semibold))
                                    .foregroundColor(.gray)
                                Text(LocalizedStringKey(nounString), comment: "Sentence composed of 2 variables to describe how many relays a note was found on. In source English, the first variable is the number of relays, and the second variable is 'Relay' or 'Relays'.")
                                    .font(.footnote)
                                    .foregroundColor(.gray)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding([.top, .leading, .trailing])
                
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
                Task {
                    await self.bar.update(damus: self.damus, evid: target)
                    await self.updateSeenRelays()
                }
            }
            .compositingGroup()
            .onAppear {
                Task { await self.updateSeenRelays() }
            }
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

    func updateSeenRelays() async {
        // Fetch relays on the network actor then hop to main to publish state.
        let relays = await Array(damus.nostrNetwork.relayURLsThatSawNote(id: event.id) ?? [])
        await MainActor.run {
            self.relays = relays
        }
    }
}

struct SelectedEventView_Previews: PreviewProvider {
    static var previews: some View {
        SelectedEventView(damus: test_damus_state, event: test_note, size: .selected)
    }
}
