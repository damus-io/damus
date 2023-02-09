//
//  RelayConfigView.swift
//  damus
//
//  Created by William Casarin on 2023-01-30.
//

import SwiftUI

struct RelayConfigView: View {
    let state: DamusState
    @State var new_relay: String = ""
    @State var show_add_relay: Bool = false
    @State var relays: [RelayDescriptor]
    
    init(state: DamusState) {
        self.state = state
        _relays = State(initialValue: state.pool.descriptors)
    }
    
    var recommended: [RelayDescriptor] {
        let rs: [RelayDescriptor] = []
        return BOOTSTRAP_RELAYS.reduce(into: rs) { (xs, x) in
            if let _ = state.pool.get_relay(x) {
            } else {
                xs.append(RelayDescriptor(url: URL(string: x)!, info: .rw))
            }
        }
    }
    
    var body: some View {
        MainContent
        .onReceive(handle_notify(.relays_changed)) { _ in
            self.relays = state.pool.descriptors
        }
        .sheet(isPresented: $show_add_relay) {
            AddRelayView(show_add_relay: $show_add_relay, relay: $new_relay) { m_relay in
                guard var relay = m_relay else {
                    return
                }
                
                if relay.starts(with: "wss://") == false && relay.starts(with: "ws://") == false {
                    relay = "wss://" + relay
                }
                
                guard let url = URL(string: relay) else {
                    return
                }
                
                guard let ev = state.contacts.event else {
                    return
                }
                
                guard let privkey = state.keypair.privkey else {
                    return
                }
                
                let info = RelayInfo.rw
                
                guard (try? state.pool.add_relay(url, info: info)) != nil else {
                    return
                }
                
                state.pool.connect(to: [relay])
                
                guard let new_ev = add_relay(ev: ev, privkey: privkey, current_relays: state.pool.descriptors, relay: relay, info: info) else {
                    return
                }
                
                process_contact_event(state: state, ev: ev)
                
                state.pool.send(.event(new_ev))
            }
        }
    }
    
    var MainContent: some View {
        Form {
            Section {
                List(Array(relays), id: \.url) { relay in
                    RelayView(state: state, relay: relay.url.absoluteString)
                }
            } header: {
                HStack {
                    Text("Relays", comment: "Header text for relay server list for configuration.")
                    Spacer()
                    Button(action: { show_add_relay = true }) {
                        Image(systemName: "plus")
                            .foregroundColor(.accentColor)
                    }
                }
            }
            
            if recommended.count > 0 {
                Section(NSLocalizedString("Recommended Relays", comment: "Section title for recommend relay servers that could be added as part of configuration")) {
                    List(recommended, id: \.url) { r in
                        RecommendedRelayView(damus: state, relay: r.url.absoluteString)
                    }
                }
            }
        }
    }
}

struct RelayConfigView_Previews: PreviewProvider {
    static var previews: some View {
        RelayConfigView(state: test_damus_state())
    }
}
