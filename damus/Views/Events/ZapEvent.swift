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
            HStack(alignment: .center) {
                Text("⚡️ \(format_msats(zap.invoice.amount))", comment: "Text indicating the zap amount. i.e. number of satoshis that were tipped to a user")
                    .font(.headline)
                    .padding([.top], 2)
                
                if zap.private_request != nil {
                    Image(systemName: "lock.fill")
                        .foregroundColor(DamusColors.green)
                        .help(NSLocalizedString("Only you can see this message and who sent it.", comment: "Help text on green lock icon that explains that only the current user can see the message of a zap event and who sent the zap."))
                }
            }

            if let priv = zap.private_request {
                
                TextEvent(damus: damus, event: priv, pubkey: priv.pubkey, options: [.no_action_bar, .no_replying_to])
                    .padding([.top], 1)
            } else {
                TextEvent(damus: damus, event: zap.request.ev, pubkey: zap.request.ev.pubkey, options: [.no_action_bar, .no_replying_to])
                    .padding([.top], 1)
            }
        }
    }
}


let test_zap_invoice = ZapInvoice(description: .description("description"), amount: 10000, string: "lnbc1", expiry: 1000000, payment_hash: Data(), created_at: 1000000)
let test_zap_request_ev = NostrEvent(content: "hi", pubkey: "pk", kind: 9734)
let test_zap_request = ZapRequest(ev: test_zap_request_ev)
let test_zap = Zap(event: test_event, invoice: test_zap_invoice, zapper: "zapper", target: .profile("pk"), request: test_zap_request, is_anon: false, private_request: nil)

let test_private_zap = Zap(event: test_event, invoice: test_zap_invoice, zapper: "zapper", target: .profile("pk"), request: test_zap_request, is_anon: false, private_request: test_event)

struct ZapEvent_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ZapEvent(damus: test_damus_state(), zap: test_zap)
            
            ZapEvent(damus: test_damus_state(), zap: test_private_zap)
        }
    }
}
