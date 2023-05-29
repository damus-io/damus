//
//  SignalView.swift
//  damus
//
//  Created by William Casarin on 2023-04-14.
//

import SwiftUI

struct SignalView: View {
    let state: DamusState
    
    @ObservedObject var signal: SignalModel
    
    @StateObject var profile: ProfileModel
    
    var body: some View {
        Group {
            if signal.signal != signal.max_signal {
                NavigationLink(destination: RelayConfigView(state: state, profile: profile)) {
                    Text("\(signal.signal)/\(signal.max_signal)", comment: "Fraction of how many of the user's relay servers that are operational.")
                        .font(.callout)
                        .foregroundColor(.gray)
                }
            } else {
                Text("")
            }
        }
                                        
    }
}

struct SignalView_Previews: PreviewProvider {
    static var previews: some View {
        let test_state = test_damus_state()
         let profile = ProfileModel(pubkey: test_state.pubkey, damus: test_state)

         SignalView(state: test_state, signal: SignalModel(signal: 5, max_signal: 10), profile: profile)
    }
}
