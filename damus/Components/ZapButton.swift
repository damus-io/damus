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

class ZapButtonModel: ObservableObject {
    var invoice: String? = nil
    @Published var zapping: String = ""
    @Published var showing_select_wallet: Bool = false
    @Published var showing_zap_customizer: Bool = false
}

struct ZapButton: View {
    let damus_state: DamusState
    let event: NostrEvent
    let lnurl: String
    
    @ObservedObject var zaps: ZapsDataModel
    @StateObject var button: ZapButtonModel = ZapButtonModel()
    
    var our_zap: Zapping? {
        zaps.zaps.first(where: { z in z.request.pubkey == damus_state.pubkey })
    }
    
    var zap_img: String {
        switch our_zap {
        case .none:
            return "bolt"
        case .zap:
            return "bolt.fill"
        case .pending:
            return "bolt.fill"
        }
    }
    
    var zap_color: Color {
        if our_zap == nil {
            return Color.gray
        }
        
        // always orange !
        return Color.orange
            /*
        if our_zap.is_paid {
            return Color.orange
        } else {
            return Color.yellow
        }
             */
    }
    
    func tap() {
        guard let our_zap else {
            send_zap(damus_state: damus_state, event: event, lnurl: lnurl, is_custom: false, comment: nil, amount_sats: nil, zap_type: damus_state.settings.default_zap_type)
            return
        }
        
        // we've tapped and we have a zap already... cancel if we can
        switch our_zap {
        case .zap:
            // can't undo a zap we've already sent
            // if we want to send more zaps we will need to long-press
            print("cancel_zap: we already have a real zap, can't cancel")
            break
        case .pending(let pzap):
            guard let res = cancel_zap(zap: pzap, box: damus_state.postbox, zapcache: damus_state.zaps, evcache: damus_state.events) else {
                
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                return
            }
            
            UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
            
            switch res {
            case .send_err(let cancel_err):
                switch cancel_err {
                case .nothing_to_cancel:
                    print("cancel_zap: got nothing_to_cancel in pending")
                    break
                case .not_delayed:
                    print("cancel_zap: got not_delayed in pending")
                    break
                case .too_late:
                    print("cancel_zap: got too_late in pending")
                    break
                }
            case .already_confirmed:
                print("cancel_zap: got already_confirmed in pending")
                break
            case .not_nwc:
                print("cancel_zap: got not_nwc in pending")
                break
            }
        }
                
            
    }
    
    var body: some View {
        HStack(spacing: 4) {
            Button(action: {
            }, label: {
                Image(systemName: zap_img)
                    .foregroundColor(zap_color)
                    .font(.footnote.weight(.medium))
            })

            if zaps.zap_total > 0 {
                Text(verbatim: format_msats_abbrev(zaps.zap_total))
                    .font(.footnote)
                    .foregroundColor(zap_color)
            }
        }
        .accessibilityLabel(NSLocalizedString("Zap", comment: "Accessibility label for zap button"))
        .simultaneousGesture(LongPressGesture().onEnded {_  in
            button.showing_zap_customizer = true
        })
        .highPriorityGesture(TapGesture().onEnded {
            tap()
        })
        .sheet(isPresented: $button.showing_zap_customizer) {
            CustomizeZapView(state: damus_state, event: event, lnurl: lnurl)
        }
        .sheet(isPresented: $button.showing_select_wallet, onDismiss: {button.showing_select_wallet = false}) {
            SelectWalletView(default_wallet: damus_state.settings.default_wallet, showingSelectWallet: $button.showing_select_wallet, our_pubkey: damus_state.pubkey, invoice: button.invoice ?? "")
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
                if damus_state.settings.show_wallet_selector {
                    self.button.invoice = inv
                    self.button.showing_select_wallet = true
                } else {
                    let wallet = damus_state.settings.default_wallet.model
                    open_with_wallet(wallet: wallet, invoice: inv)
                }
            }
        }
    }
}


struct ZapButton_Previews: PreviewProvider {
    static var previews: some View {
        let pending_zap = PendingZap(amount_msat: 1000, target: ZapTarget.note(id: "noteid", author: "author"), request: .normal(test_zap_request), type: .pub, state: .external(.init(state: .fetching_invoice)))
        let zaps = ZapsDataModel([.pending(pending_zap)])
        
        ZapButton(damus_state: test_damus_state(), event: test_event, lnurl: "lnurl", zaps: zaps)
    }
}



func initial_pending_zap_state(settings: UserSettingsStore) -> PendingZapState {
    if let url = settings.nostr_wallet_connect,
       let nwc = WalletConnectURL(str: url)
    {
        return .nwc(NWCPendingZapState(state: .fetching_invoice, url: nwc))
    }
    
    return .external(ExtPendingZapState(state: .fetching_invoice))
}

func send_zap(damus_state: DamusState, event: NostrEvent, lnurl: String, is_custom: Bool, comment: String?, amount_sats: Int?, zap_type: ZapType) {
    guard let keypair = damus_state.keypair.to_full() else {
        return
    }
    
    // Only take the first 10 because reasons
    let relays = Array(damus_state.pool.our_descriptors.prefix(10))
    let target = ZapTarget.note(id: event.id, author: event.pubkey)
    let content = comment ?? ""
    
    guard let mzapreq = make_zap_request_event(keypair: keypair, content: content, relays: relays, target: target, zap_type: zap_type) else {
        // this should never happen
        return
    }
    
    let amount_msat = Int64(amount_sats ?? damus_state.settings.default_zap_amount) * 1000
    let pending_zap_state = initial_pending_zap_state(settings: damus_state.settings)
    let pending_zap = PendingZap(amount_msat: amount_msat, target: target, request: mzapreq, type: zap_type, state: pending_zap_state)
    let zapreq = mzapreq.potentially_anon_outer_request.ev
    let reqid = ZapRequestId(from_makezap: mzapreq)
    
    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
    damus_state.add_zap(zap: .pending(pending_zap))
    
    Task {
        var mpayreq = damus_state.lnurls.lookup(target.pubkey)
        if mpayreq == nil {
            mpayreq = await fetch_static_payreq(lnurl)
        }
        
        guard let payreq = mpayreq else {
            // TODO: show error
            DispatchQueue.main.async {
                remove_zap(reqid: reqid, zapcache: damus_state.zaps, evcache: damus_state.events)
                let typ = ZappingEventType.failed(.bad_lnurl)
                let ev = ZappingEvent(is_custom: is_custom, type: typ, event: event)
                notify(.zapping, ev)
            }
            return
        }
        
        DispatchQueue.main.async {
            damus_state.lnurls.endpoints[target.pubkey] = payreq
        }
        
        guard let inv = await fetch_zap_invoice(payreq, zapreq: zapreq, msats: amount_msat, zap_type: zap_type, comment: comment) else {
            DispatchQueue.main.async {
                remove_zap(reqid: reqid, zapcache: damus_state.zaps, evcache: damus_state.events)
                let typ = ZappingEventType.failed(.fetching_invoice)
                let ev = ZappingEvent(is_custom: is_custom, type: typ, event: event)
                notify(.zapping, ev)
            }
            return
        }
        
        DispatchQueue.main.async {
            
            switch pending_zap_state {
            case .nwc(let nwc_state):
                // don't both continuing, user has canceled
                if case .cancel_fetching_invoice = nwc_state.state {
                    remove_zap(reqid: reqid, zapcache: damus_state.zaps, evcache: damus_state.events)
                    return
                }
                
                var flusher: OnFlush? = nil
                // Don't donate on custom zaps
                if !is_custom && damus_state.settings.donation_percent > 0 {
                    flusher = .once({ pe in
                        // send donation zap when the pending zap is flushed, this allows user to cancel and not send a donation
                        Task.init { @MainActor in
                            await send_donation_zap(pool: damus_state.pool, postbox: damus_state.postbox, nwc: nwc_state.url, percent: damus_state.settings.donation_percent, base_msats: amount_msat)
                        }
                    })
                }
                
                let nwc_req = nwc_pay(url: nwc_state.url,  pool: damus_state.pool, post: damus_state.postbox, invoice: inv, on_flush: flusher)
                
                guard let nwc_req, case .nwc(let pzap_state) = pending_zap_state else {
                    return
                }
                
                if pzap_state.update_state(state: .postbox_pending(nwc_req)) {
                    // we don't need to trigger a ZapsDataModel update here
                }
            case .external(let pending_ext):
                pending_ext.state = .done
                let ev = ZappingEvent(is_custom: is_custom, type: .got_zap_invoice(inv), event: event)
                notify(.zapping, ev)
            }
        }
    }
    
    return
}

enum CancelZapErr {
    case send_err(CancelSendErr)
    case already_confirmed
    case not_nwc
}

func cancel_zap(zap: PendingZap, box: PostBox, zapcache: Zaps, evcache: EventCache) -> CancelZapErr? {
    guard case .nwc(let nwc_state) = zap.state else {
        return .not_nwc
    }
    
    switch nwc_state.state {
    case .fetching_invoice:
        if nwc_state.update_state(state: .cancel_fetching_invoice) {
            // we don't need to update the ZapsDataModel here
        }
        // let the code that retrieves the invoice remove the zap, because
        // it still needs access to this pending zap to know to cancel
        
    case .cancel_fetching_invoice:
        // already cancelling?
        print("cancel_zap: already cancelling")
        return nil
        
    case .confirmed:
        return .already_confirmed
        
    case .postbox_pending(let nwc_req):
        if let err = box.cancel_send(evid: nwc_req.id) {
            return .send_err(err)
        }
        let reqid = ZapRequestId(from_pending: zap)
        remove_zap(reqid: reqid, zapcache: zapcache, evcache: evcache)
        
    case .failed:
        let reqid = ZapRequestId(from_pending: zap)
        remove_zap(reqid: reqid, zapcache: zapcache, evcache: evcache)
    }
    
    return nil
}
