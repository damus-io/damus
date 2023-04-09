//
//  ZapButton.swift
//  damus
//
//  Created by William Casarin on 2023-01-17.
//

import SwiftUI

enum ZappingEventType {
    case failed(ZappingError)
    case got_zap_invoice(String)
}

enum ZappingError {
    case fetching_invoice
    case bad_lnurl
}

struct ZappingEvent {
    let is_custom: Bool
    let type: ZappingEventType
    let event: NostrEvent
}

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
    @State var showing_zap_customizer: Bool = false
    @State var is_charging: Bool = false
    
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
        
        if is_charging {
            return Color.yellow
        }
        
        if !zapping {
            return nil
        }
        
        return Color.yellow
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
            }, label: {
                Image(systemName: zap_img)
                    .foregroundColor(zap_color == nil ? Color.gray : zap_color!)
                    .font(.footnote.weight(.medium))
            })
            .simultaneousGesture(LongPressGesture().onEnded {_  in
                guard !zapping else {
                    return
                }
                
                self.showing_zap_customizer = true
            })
            .highPriorityGesture(TapGesture().onEnded {_  in
                guard !zapping else {
                    return
                }
                
                send_zap(damus_state: damus_state, event: event, lnurl: lnurl, is_custom: false, comment: nil, amount_sats: nil, zap_type: ZapType.pub)
                self.zapping = true
            })
            .accessibilityLabel(NSLocalizedString("Zap", comment: "Accessibility label for zap button"))

            if bar.zap_total > 0 {
                Text(verbatim: format_msats_abbrev(bar.zap_total))
                    .font(.footnote)
                    .foregroundColor(bar.zapped ? Color.orange : Color.gray)
            }
        }
        .sheet(isPresented: $showing_zap_customizer) {
            CustomizeZapView(state: damus_state, event: event, lnurl: lnurl)
        }
        .sheet(isPresented: $showing_select_wallet, onDismiss: {showing_select_wallet = false}) {
            SelectWalletView(showingSelectWallet: $showing_select_wallet, our_pubkey: damus_state.pubkey, invoice: invoice)
        }
        .onReceive(handle_notify(.zapping)) { notif in
            let zap_ev = notif.object as! ZappingEvent
            
            guard zap_ev.event.id == self.event.id else {
                return
            }
            
            guard !zap_ev.is_custom else {
                return
            }
            
            switch zap_ev.type {
            case .failed:
                break
            case .got_zap_invoice(let inv):
                if should_show_wallet_selector(damus_state.pubkey) {
                    self.invoice = inv
                    self.showing_select_wallet = true
                } else {
                    open_with_wallet(wallet: get_default_wallet(damus_state.pubkey).model, invoice: inv)
                }
            }
            
            self.zapping = false
        }
    }
}


struct ZapButton_Previews: PreviewProvider {
    static var previews: some View {
        let bar = ActionBarModel(likes: 0, boosts: 0, zaps: 10, zap_total: 15623414, replies: 2, our_like: nil, our_boost: nil, our_zap: nil, our_reply: nil)
        ZapButton(damus_state: test_damus_state(), event: test_event, lnurl: "lnurl", bar: bar)
    }
}



func send_zap(damus_state: DamusState, event: NostrEvent, lnurl: String, is_custom: Bool, comment: String?, amount_sats: Int?, zap_type: ZapType) {
    guard let keypair = damus_state.keypair.to_full() else {
        return
    }
    
    // Only take the first 10 because reasons
    let relays = Array(damus_state.pool.descriptors.prefix(10))
    let target = ZapTarget.note(id: event.id, author: event.pubkey)
    let content = comment ?? ""
    
    let zapreq = make_zap_request_event(keypair: keypair, content: content, relays: relays, target: target, zap_type: zap_type)
    
    Task {
        var mpayreq = damus_state.lnurls.lookup(target.pubkey)
        if mpayreq == nil {
            mpayreq = await fetch_static_payreq(lnurl)
        }
        
        guard let payreq = mpayreq else {
            // TODO: show error
            DispatchQueue.main.async {
                let typ = ZappingEventType.failed(.bad_lnurl)
                let ev = ZappingEvent(is_custom: is_custom, type: typ, event: event)
                notify(.zapping, ev)
            }
            return
        }
        
        DispatchQueue.main.async {
            damus_state.lnurls.endpoints[target.pubkey] = payreq
        }
        
        let zap_amount = amount_sats ?? get_default_zap_amount(pubkey: damus_state.pubkey) ?? 1000
        
        guard let inv = await fetch_zap_invoice(payreq, zapreq: zapreq, sats: zap_amount, zap_type: zap_type, comment: comment) else {
            DispatchQueue.main.async {
                let typ = ZappingEventType.failed(.fetching_invoice)
                let ev = ZappingEvent(is_custom: is_custom, type: typ, event: event)
                notify(.zapping, ev)
            }
            return
        }
        
        DispatchQueue.main.async {
            let ev = ZappingEvent(is_custom: is_custom, type: .got_zap_invoice(inv), event: event)
            notify(.zapping, ev)
        }
    }
    
    return
}
