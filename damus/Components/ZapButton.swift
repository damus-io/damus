//
//  ZapButton.swift
//  damus
//
//  Created by William Casarin on 2023-01-17.
//

import SwiftUI

struct ZapButton: View {
    let damus_state: DamusState
    let event: NostrEvent
    let lnurl: String
    
    @ObservedObject var bar: ActionBarModel
    
    @State var zapping: Bool = false
    @State var invoice: String = ""
    @State var slider_value: Double = 0.0
    @State var slider_visible: Bool = false
    @State var showing_select_wallet: Bool = false
    
    func send_zap() {
        guard let privkey = damus_state.keypair.privkey else {
            return
        }
        
        // Only take the first 10 because reasons
        let relays = Array(damus_state.pool.descriptors.prefix(10))
        let target = ZapTarget.note(id: event.id, author: event.pubkey)
        // TODO: gather comment?
        let content = ""
        let zapreq = make_zap_request_event(pubkey: damus_state.pubkey, privkey: privkey, content: content, relays: relays, target: target)
        
        zapping = true
        
        Task {
            var mpayreq = damus_state.lnurls.lookup(target.pubkey)
            if mpayreq == nil {
                mpayreq = await fetch_static_payreq(lnurl)
            }
            
            guard let payreq = mpayreq else {
                // TODO: show error
                DispatchQueue.main.async {
                    zapping = false
                }
                return
            }
            
            DispatchQueue.main.async {
                damus_state.lnurls.endpoints[target.pubkey] = payreq
            }
            
            let zap_amount = get_default_zap_amount(pubkey: damus_state.pubkey) ?? 1000
            guard let inv = await fetch_zap_invoice(payreq, zapreq: zapreq, sats: zap_amount) else {
                DispatchQueue.main.async {
                    zapping = false
                }
                return
            }
            
            DispatchQueue.main.async {
                zapping = false
                
                if should_show_wallet_selector(damus_state.pubkey) {
                    self.invoice = inv
                    self.showing_select_wallet = true
                } else {
                    open_with_wallet(wallet: get_default_wallet(damus_state.pubkey).model, invoice: inv)
                }
            }
        }
        
        //damus_state.pool.send(.event(zapreq))
    }
    
    var zap_img: String {
        if bar.zapped {
            return "bolt.fill"
        }
        
        if !zapping {
            return "bolt"
        }
        
        return "bolt.horizontal.fill"
    }
    
    var zap_color: Color? {
        if bar.zapped {
            return Color.orange
        }
        
        if !zapping {
            return nil
        }
        
        return Color.yellow
    }
    
    var body: some View {
        ZStack {
            EventActionButton(img: zap_img, col: zap_color) {
                if bar.zapped {
                    //notify(.delete, bar.our_tip)
                } else if !zapping {
                    send_zap()
                }
            }
            .accessibilityLabel(NSLocalizedString("Zap", comment: "Accessibility label for zap button"))
            
            Text("\(bar.zap_total > 0 ? "\(format_msats_abbrev(bar.zap_total))" : "")")
                .offset(x: 22)
                .font(.footnote)
                .foregroundColor(bar.zapped ? Color.orange : Color.gray)
        }
        .sheet(isPresented: $showing_select_wallet, onDismiss: {showing_select_wallet = false}) {
            SelectWalletView(showingSelectWallet: $showing_select_wallet, our_pubkey: damus_state.pubkey, invoice: invoice)
        }
    }
}


struct ZapButton_Previews: PreviewProvider {
    static var previews: some View {
        let bar = ActionBarModel(likes: 0, boosts: 0, zaps: 10, zap_total: 15623414, our_like: nil, our_boost: nil, our_zap: nil)
        ZapButton(damus_state: test_damus_state(), event: test_event, lnurl: "lnurl", bar: bar)
    }
}

