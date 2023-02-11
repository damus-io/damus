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
    @State var is_show_relay_explanation: Bool = true

    @Environment(\.dismiss) var dismiss

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
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
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
                if is_show_relay_explanation {
                    relayExplanationView
                }
            } header: {
                if is_show_relay_explanation {
                    relayCountLabel
                }
            }

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

extension RelayConfigView {
    private var relayExplanationView: some View {
        ZStack(alignment: .center) {
            relayExplanationBackground

            relayExplanationContent.padding(13)
        }
        .listRowBackground(Color.primary)
        .listRowInsets(.init(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0)))
    }

    private var relayExplanationBackground: some View {
        RoundedRectangle(cornerRadius: 9)
            .padding(.all, 1.5)
            .foregroundColor(Color(.systemGroupedBackground))
    }

    private var relayExplanationContent: some View {
        VStack {
            HStack(alignment: .top, spacing: 10) {
                Image("relay-explanation-avatar")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)

                explanationText
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(alignment: .center, spacing: 10) {
                gotitButton

                learnmoreButton
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private var explanationText: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("What’s a relay?")
                .font(.system(size: 17, weight: .bold, design: .default))
                .fixedSize(horizontal: false, vertical: true)

            Text("It’s a server that you send notes to and receive notes from.")
                .font(.system(size: 15, weight: .medium, design: .default))
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 3)

            Text("What are the numbers in the top right?")
                .font(.system(size: 17, weight: .bold, design: .default))
                .fixedSize(horizontal: false, vertical: true)

            Text("The top number displays the number of relays you are connected to. The bottom number shows the count of all the relays you want to connect to.")
                .font(.system(size: 15, weight: .medium, design: .default))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var gotitButton: some View {
        Button {
            withAnimation { is_show_relay_explanation = false }
        } label: {
            Text("Got it")
                .foregroundColor(.accentColor)
                .font(.system(size: 15, weight: .bold))
                .padding(.init(top: 10, leading: 18, bottom: 10, trailing: 18))
                .overlay(.gray, in: RoundedRectangle(cornerRadius: 20).stroke(style: .init(lineWidth: 1)))
        }
        .buttonStyle(.borderless)
        .background(Color(.systemGroupedBackground), in: RoundedRectangle(cornerRadius: 20))
    }

    private var learnmoreButton: some View {
        Button {
            guard let url = URL(string: "https://nostr-resources.com/") else { return }
            UIApplication.shared.open(url)
        } label: {
            Text("Learn more")
                .foregroundColor(.white)
                .font(.system(size: 15, weight: .bold))
                .padding(.init(top: 10, leading: 18, bottom: 10, trailing: 18))
        }
        .buttonStyle(.borderless)
        .background(Color.accentColor, in: RoundedRectangle(cornerRadius: 20))
    }

    private var relayCountLabel: some View {
        ZStack(alignment: .center) {
            Circle()
                .frame(width: 50, height: 50)
                .foregroundColor(.clear)
                .overlay(Color.accentColor, in: Circle().stroke(style: .init(lineWidth: 2)))
            Text("\(state.pool.relays.count - state.pool.num_connecting)/\(state.pool.relays.count)")
                .font(.system(size: 15, weight: .bold))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

struct RelayConfigView_Previews: PreviewProvider {
    static var previews: some View {
        RelayConfigView(state: test_damus_state())
    }
}
