//
//  ZapUserView.swift
//  damus
//
//  Created by William Casarin on 2023-06-22.
//

import SwiftUI

struct ZapUserView: View {
    let state: DamusState
    let pubkey: Pubkey

    var body: some View {
        HStack(alignment: .center) {
            Text("Zap")
                .font(.title2)
            
            UserView(damus_state: state, pubkey: pubkey, spacer: false)
        }
    }
}

struct ZapUserView_Previews: PreviewProvider {
    static var previews: some View {
        ZapUserView(state: test_damus_state, pubkey: ANON_PUBKEY)
    }
}
