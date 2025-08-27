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
    
    var body: some View {
        Group {
            if signal.signal != signal.max_signal {
                NavigationLink(value: Route.RelayConfig) {
                    Text("\(signal.signal)/\(signal.max_signal)", comment: "Fraction of how many of the user's relay servers that are operational.")
                        .font(.callout)
                        .foregroundColor(.gray)
                }
                .frame(width:50,height:30)
                .disabled(signal.signal == signal.max_signal)
            }
        }
                                        
    }
}

struct SignalView_Previews: PreviewProvider {
    static var previews: some View {
        SignalView(state: test_damus_state, signal: SignalModel(signal: 5, max_signal: 10))
    }
}
