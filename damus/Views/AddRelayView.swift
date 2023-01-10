//
//  AddRelayView.swift
//  damus
//
//  Created by William Casarin on 2022-06-09.
//

import SwiftUI

struct AddRelayView: View {
    @Binding var show_add_relay: Bool
    @Binding var relay: String
    
    let action: (String?) -> Void
    
    var body: some View {
        VStack(alignment: .leading) {
            Form {
                Section(NSLocalizedString("Add Relay", comment: "Label for section for adding a relay server.")) {
                    ZStack(alignment: .leading) {
                        HStack{
                            TextField(NSLocalizedString("wss://some.relay.com", comment: "Placeholder example for relay server address."), text: $relay)
                                .padding(2)
                                .padding(.leading, 25)
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.never)
                            
                            Label("", systemImage: "xmark.circle.fill")
                                .foregroundColor(.blue)
                                .padding(.trailing, -25.0)
                                .opacity((relay == "") ? 0.0 : 1.0)
                                .onTapGesture {
                                    self.relay = ""
                                }
                        }
                        
                        Label("", systemImage: "doc.on.clipboard")
                            .padding(.leading, -10)
                            .onTapGesture {
                            if let pastedrelay = UIPasteboard.general.string {
                                self.relay = pastedrelay
                            }
                        }
                    }
                }
            }
            
            VStack {
                HStack {
                    Button(NSLocalizedString("Cancel", comment: "Button to cancel out of view adding user inputted relay.")) {
                        show_add_relay = false
                        action(nil)
                    }
                    .contentShape(Rectangle())
                    
                    Spacer()
                    
                    Button(NSLocalizedString("Add", comment: "Button to confirm adding user inputted relay.")) {
                        show_add_relay = false
                        action(relay)
                        relay = ""
                    }
                    .buttonStyle(.borderedProminent)
                    .contentShape(Rectangle())
                }
                .padding()
            }
        }
    }
}

struct AddRelayView_Previews: PreviewProvider {
    @State static var show: Bool = true
    @State static var relay: String = ""
    
    static var previews: some View {
        AddRelayView(show_add_relay: $show, relay: $relay, action: {_ in })
    }
}
