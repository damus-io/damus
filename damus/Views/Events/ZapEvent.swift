//
//  ZapEvent.swift
//  damus
//
//  Created by William Casarin on 2023-02-03.
//

import SwiftUI

struct ZapEvent: View {
    let damus: DamusState
    let zap: Zap
    
    var body: some View {
        VStack(alignment: .leading) {
            Text("⚡️ \(format_msats(zap.invoice.amount))")
                .font(.headline)
                .padding([.top], 2)

            TextEvent(damus: damus, event: zap.request.ev, pubkey: zap.request.ev.pubkey, has_action_bar: false, booster_pubkey: nil)
                .padding([.top], 1)
        }
    }
}

/*
struct ZapEvent_Previews: PreviewProvider {
    static var previews: some View {
        ZapEvent()
    }
}

*/
