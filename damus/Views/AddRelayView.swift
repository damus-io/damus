//
//  AddRelayView.swift
//  damus
//
//  Created by William Casarin on 2022-06-09.
//

import SwiftUI

struct AddRelayView: View {
    @Binding var relay: String
    
    var body: some View {
        ZStack(alignment: .leading) {
            HStack{
                TextField(NSLocalizedString("wss://some.relay.com", comment: "Placeholder example for relay server address."), text: $relay)
                    .padding(2)
                    .padding(.leading, 25)
                    .autocorrectionDisabled(true)
                    .textInputAutocapitalization(.never)
                
                Label("", systemImage: "xmark.circle.fill")
                    .foregroundColor(.accentColor)
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

struct AddRelayView_Previews: PreviewProvider {
    @State static var relay: String = ""
    
    static var previews: some View {
        AddRelayView(relay: $relay)
    }
}
