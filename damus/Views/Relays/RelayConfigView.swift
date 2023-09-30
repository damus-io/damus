//
//  RelayConfigView.swift
//  damus
//
//  Created by William Casarin on 2023-01-30.
//

import SwiftUI

struct RelayConfigView: View {
    let state: DamusState
    @State var relays: [RelayDescriptor]
    @State private var showActionButtons = false
    @State var show_add_relay: Bool = false
    
    @Environment(\.dismiss) var dismiss
    
    init(state: DamusState) {
        self.state = state
        _relays = State(initialValue: state.pool.our_descriptors)
    }
    
    var recommended: [RelayDescriptor] {
        let rs: [RelayDescriptor] = []
        return BOOTSTRAP_RELAYS.reduce(into: rs) { xs, x in
            if state.pool.get_relay(x) == nil, let url = RelayURL(x) {
                xs.append(RelayDescriptor(url: url, info: .rw))
            }
        }
    }
    
    var body: some View {
        MainContent
        .onReceive(handle_notify(.relays_changed)) { _ in
            self.relays = state.pool.our_descriptors
        }
        .onReceive(handle_notify(.switched_timeline)) { _ in
            dismiss()
        }
    }
    
    var MainContent: some View {
        VStack {
            Divider()
            
            if recommended.count > 0 {
                VStack {
                    Text("Recommended relays", comment: "Title for view of recommended relays.")
                        .foregroundStyle(DamusLightGradient.gradient)
                        .padding(10)
                        .background {
                            RoundedRectangle(cornerRadius: 15)
                                .stroke(DamusLightGradient.gradient)
                        }
                        .padding(.vertical)
                    
                    HStack(spacing: 20) {
                        ForEach(recommended, id: \.url) { r in
                            RecommendedRelayView(damus: state, relay: r.url.id)
                        }
                    }
                    .padding()
                }
                .frame(minWidth: 250, maxWidth: .infinity, minHeight: 250, alignment: .center)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(DamusLightGradient.gradient.opacity(0.15), strokeBorder: DamusLightGradient.gradient, lineWidth: 1)
                }
                .padding(.horizontal)
            }
            
            HStack {
                Text(NSLocalizedString("My Relays", comment: "Section title for relay servers that the user is connected to."))
                    .font(.system(size: 32, weight: .bold))

                Spacer()
                
                Button(action: {
                    show_add_relay.toggle()
                }) {
                    HStack {
                        Text(verbatim: "Add relay")
                            .padding(10)
                    }
                }
                .buttonStyle(NeutralButtonStyle())
            }
            .padding(25)
            
            List(Array(relays), id: \.url) { relay in
                RelayView(state: state, relay: relay.url.id, showActionButtons: $showActionButtons)
            }
            .listStyle(PlainListStyle())
        }
        .navigationTitle(NSLocalizedString("Relays", comment: "Title of relays view"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $show_add_relay, onDismiss: { self.show_add_relay = false }) {
            if #available(iOS 16.0, *) {
                AddRelayView(state: state)
                    .presentationDetents([.height(300)])
                    .presentationDragIndicator(.visible)
            } else {
                AddRelayView(state: state)
            }
        }
        .toolbar {
            if state.keypair.privkey != nil {
                if showActionButtons {
                    Button("Done") {
                        withAnimation {
                            showActionButtons.toggle()
                        }
                    }
                } else {
                    Button("Edit") {
                        withAnimation {
                            showActionButtons.toggle()
                        }
                    }
                }
            }
        }
    }
}

struct RelayConfigView_Previews: PreviewProvider {
    static var previews: some View {
        RelayConfigView(state: test_damus_state)
    }
}
