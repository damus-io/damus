//
//  AddRelayView.swift
//  damus
//
//  Created by William Casarin on 2022-06-09.
//

import SwiftUI

struct AddRelayView: View {
    let state: DamusState
    @State var new_relay: String = ""
    @State var relayAddErrorTitle: String? = nil
    @State var relayAddErrorMessage: String? = nil
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        VStack {
            Text("Add relay", comment: "Title text to indicate user to an add a relay.")
                .font(.system(size: 20, weight: .bold))
                .padding(.vertical)
            
            Divider()
                .padding(.bottom)
            
            HStack {
                Label("", image: "copy2")
                    .onTapGesture {
                    if let pastedrelay = UIPasteboard.general.string {
                        self.new_relay = pastedrelay
                    }
                }
                TextField(NSLocalizedString("wss://some.relay.com", comment: "Placeholder example for relay server address."), text: $new_relay)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                
                Label("", image: "close-circle")
                    .foregroundColor(.accentColor)
                    .opacity((new_relay == "") ? 0.0 : 1.0)
                    .onTapGesture {
                        self.new_relay = ""
                    }
            }
            .padding(10)
            .background(.secondary.opacity(0.2))
            .cornerRadius(10)
            
            if let errorMessage = relayAddErrorMessage {
                VStack(spacing: 0) {
                    HStack(alignment: .top) {
                        Text(relayAddErrorTitle ?? "Error")
                            .bold()
                            .foregroundColor(DamusColors.dangerSecondary)
                            .padding(.leading)
                        Spacer()
                        Button(action: {
                            relayAddErrorTitle = nil      // Clear error title
                            relayAddErrorMessage = nil    // Clear error message
                            self.new_relay = ""
                        }, label: {
                            Image("close")
                                .frame(width: 20, height: 20)
                                .foregroundColor(DamusColors.dangerSecondary)
                        })
                        .padding(.trailing)
                    }
                    
                    Text(errorMessage)
                        .foregroundColor(DamusColors.dangerSecondary)
                        .padding(.top, 10)
                }
                .frame(minWidth: 300, maxWidth: .infinity, minHeight: 120, alignment: .center)
                .background {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(DamusColors.dangerBorder, strokeBorder: .gray.opacity(0.5), lineWidth: 1)
                }
            }
            
            Button(action: {
                if new_relay.starts(with: "wss://") == false && new_relay.starts(with: "ws://") == false {
                    new_relay = "wss://" + new_relay
                }

                guard let url = RelayURL(new_relay),
                      let ev = state.contacts.event,
                      let keypair = state.keypair.to_full() else {
                    return
                }

                let info = RelayInfo.rw
                let descriptor = RelayDescriptor(url: url, info: info)

                do {
                    try state.pool.add_relay(descriptor)
                    relayAddErrorTitle = nil      // Clear error title
                    relayAddErrorMessage = nil    // Clear error message
                } catch RelayError.RelayAlreadyExists {
                    relayAddErrorTitle = NSLocalizedString("Duplicate relay", comment: "Title of the duplicate relay error message.")
                    relayAddErrorMessage = NSLocalizedString("The relay you are trying to add is already added.\nYou're all set!", comment: "An error message that appears when the user attempts to add a relay that has already been added.")
                    return
                } catch {
                    return
                }

                state.pool.connect(to: [url])

                if let new_ev = add_relay(ev: ev, keypair: keypair, current_relays: state.pool.our_descriptors, relay: url, info: info) {
                    process_contact_event(state: state, ev: ev)

                    state.pool.send(.event(new_ev))
                }

                if let relay_metadata = make_relay_metadata(relays: state.pool.our_descriptors, keypair: keypair) {
                    state.postbox.send(relay_metadata)
                }
                new_relay = ""

                this_app.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
                
                dismiss()
            }) {
                HStack {
                    Text("Add relay", comment: "Button to add a relay.")
                        .bold()
                }
                .frame(minWidth: 300, maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(GradientButtonStyle(padding: 10))
            //.disabled(!new_relay.isValidURL) <--- TODO
            .padding(.vertical)
            
            Spacer()
        }
        .padding()
    }
}

// TODO
// This works sometimes, in certain cases where the relay is valid it won't allow the user to add it
// Needs improvement
extension String {
    var isValidURL: Bool {
        let detector = try! NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        if let match = detector.firstMatch(in: self, options: [], range: NSRange(location: 0, length: self.utf16.count)) {
            // it is a link, if the match covers the whole string
            return match.range.length == self.utf16.count
        } else {
            return false
        }
    }
}

struct AddRelayView_Previews: PreviewProvider {
    @State static var relay: String = ""
    
    static var previews: some View {
        AddRelayView(state: test_damus_state)
    }
}
