//
//  ZapEvent.swift
//  damus
//
//  Created by William Casarin on 2023-02-03.
//

import SwiftUI

struct ZapEvent: View {
    let damus: DamusState
    let zap: Zapping
    let is_top_zap: Bool
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .center) {
                Image("zap.fill")
                    .foregroundColor(DamusColors.adaptableOrange)
                
                Text(verbatim: format_msats(zap.amount))
                    .font(.headline)
                
                if is_top_zap {
                    Text("Top Zap", comment: "Text indicating that this zap is the one with the highest amount of sats.")
                        .font(.caption)
                        .foregroundColor(DamusColors.mediumGrey)
                        .padding([.top], 2)
                }
                
                if zap.is_private {
                    Image("lock")
                        .foregroundColor(DamusColors.green)
                        .help(NSLocalizedString("Only you can see this message and who sent it.", comment: "Help text on green lock icon that explains that only the current user can see the message of a zap event and who sent the zap."))
                }
                
                if zap.is_pending {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(zap.is_paid ? Color.orange : DamusColors.yellow)
                        .help(NSLocalizedString("Only you can see this message and who sent it.", comment: "Help text on green lock icon that explains that only the current user can see the message of a zap event and who sent the zap."))
                }
            }

            TextEvent(damus: damus, event: zap.request.ev, pubkey: zap.request.ev.pubkey, options: [.no_action_bar, .no_replying_to])
                .padding([.top], 1)
        }
    }
}


struct ZapEvent_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ZapEvent(damus: test_damus_state, zap: .zap(test_zap), is_top_zap: true)
            
            ZapEvent(damus: test_damus_state, zap: .zap(test_private_zap), is_top_zap: false)
        }
    }
}
