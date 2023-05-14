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
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(alignment: .center) {
                Text("⚡️ \(format_msats(zap.amount))", comment: "Text indicating the zap amount. i.e. number of satoshis that were tipped to a user")
                    .font(.headline)
                    .padding([.top], 2)
                
                if zap.is_private {
                    Image(systemName: "lock.fill")
                        .foregroundColor(DamusColors.green)
                        .help(NSLocalizedString("Only you can see this message and who sent it.", comment: "Help text on green lock icon that explains that only the current user can see the message of a zap event and who sent the zap."))
                }
                
                if zap.is_pending {
                    Image(systemName: "clock.arrow.circlepath")
                        .foregroundColor(zap.is_paid ? Color.orange : DamusColors.yellow)
                        .help(NSLocalizedString("Only you can see this message and who sent it.", comment: "Help text on green lock icon that explains that only the current user can see the message of a zap event and who sent the zap."))
                }
            }

            TextEvent(damus: damus, event: zap.request, pubkey: zap.request.pubkey, options: [.no_action_bar, .no_replying_to])
                .padding([.top], 1)
        }
    }
}


let test_zap_invoice = ZapInvoice(description: .description("description"), amount: 10000, string: "lnbc1", expiry: 1000000, payment_hash: Data(), created_at: 1000000)
let test_zap_request_ev = NostrEvent(content: "hi", pubkey: "pk", kind: 9734)
let test_zap_request = ZapRequest(ev: test_zap_request_ev)
let test_zap = Zap(event: test_event, invoice: test_zap_invoice, zapper: "zapper", target: .profile("pk"), request: test_zap_request, is_anon: false, private_request: nil)

let test_private_zap = Zap(event: test_event, invoice: test_zap_invoice, zapper: "zapper", target: .profile("pk"), request: test_zap_request, is_anon: false, private_request: test_event)

let test_pending_zap = PendingZap(amount_msat: 10000, target: .note(id: "id", author: "pk"), request: .normal(test_zap_request), type: .pub, state: .external(.init(state: .fetching_invoice)))

struct ZapEvent_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            ZapEvent(damus: test_damus_state(), zap: .zap(test_zap))
            
            ZapEvent(damus: test_damus_state(), zap: .zap(test_private_zap))
        }
    }
}
