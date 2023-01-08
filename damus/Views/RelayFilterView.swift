//
//  RelayFilterView.swift
//  damus
//
//  Created by Ben Weeks on 1/8/23.
//

import SwiftUI

struct RelayFilterView: View {
    let state: DamusState
    //@State var relays: [RelayDescriptor]
    //@EnvironmentObject var user_settings: UserSettingsStore
    @State var relays: [RelayDescriptor]
    
    init(state: DamusState) {
        self.state = state
        _relays = State(initialValue: state.pool.descriptors)
    }
    
    var body: some View {
        Text("To filter your feed, please choose applicable relays from the list below:")
            .padding()
            .padding(.top, 20)
            .padding(.bottom, 0)
        
        Section {
            List(Array(relays), id: \.url) { relay in
                //RelayView(state: state, relay: relay.url.absoluteString)
                Toggle(relay.url.absoluteString, isOn: .constant(true))
                    .toggleStyle(SwitchToggleStyle(tint: .accentColor))
            }
        }
        .padding()
    }
}

struct RelayFilterView_Previews: PreviewProvider {
    static var previews: some View {
        RelayFilterView(state: test_damus_state())
    }
}
