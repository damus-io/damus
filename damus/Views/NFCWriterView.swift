//
//  NFCWriterView.swift
//  damus
//
//  Created by Ben Weeks on 24/04/2023.
//

import SwiftUI

struct NFCWriterView: View {
    let damus_state: DamusState
    private let nfcWriter = NFCWriter()
    
    var body: some View {
        VStack {
            Text("When you are ready, please hold your NFC tag to the phone and click 'Start NFC Session' then 'Write NFC tag'.")
                .padding()
            
            Text("This will then write the following to your NFC tag:")
                .padding(.top)
            
            Text("nostr:" + damus_state.pubkey.lowercased())
                .padding(.top)
            
            Button("Start NFC Session") {
                nfcWriter.beginSession()
            }
                .padding(.top)

            Button("Write NFC Tag") {
                nfcWriter.writeNDEFMessage(payload: "nostr:" + damus_state.pubkey.lowercased())
            }
                .padding(.top)
        }
        .padding()
    }
}

struct NFCWriterView_Previews: PreviewProvider {
    static var previews: some View {
        let ds = test_damus_state()
        NFCWriterView(damus_state: ds)
    }
}
