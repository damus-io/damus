//
//  WalletConnect+.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-11-27.
//

import Foundation

func make_wallet_pay_invoice_request(invoice: String) -> WalletRequest<PayInvoiceRequest> {
    let data = PayInvoiceRequest(invoice: invoice)
    return WalletRequest(method: "pay_invoice", params: data)
}

func make_wallet_balance_request() -> WalletRequest<EmptyRequest> {
    return WalletRequest(method: "get_balance", params: nil)
}

struct EmptyRequest: Codable {
}

struct PayInvoiceRequest: Codable {
    let invoice: String
}

func make_wallet_connect_request<T>(req: WalletRequest<T>, to_pk: Pubkey, keypair: FullKeypair) -> NostrEvent? {
    let tags = [to_pk.tag]
    let created_at = UInt32(Date().timeIntervalSince1970)
    guard let content = encode_json(req) else {
        return nil
    }
    return create_encrypted_event(content, to_pk: to_pk, tags: tags, keypair: keypair, created_at: created_at, kind: 23194)
}

func subscribe_to_nwc(url: WalletConnectURL, pool: RelayPool) {
    var filter = NostrFilter(kinds: [.nwc_response])
    filter.authors = [url.pubkey]
    filter.limit = 0
    let sub = NostrSubscribe(filters: [filter], sub_id: "nwc")

    pool.send(.subscribe(sub), to: [url.relay], skip_ephemeral: false)
}

@discardableResult
func nwc_pay(url: WalletConnectURL, pool: RelayPool, post: PostBox, invoice: String, delay: TimeInterval? = 5.0, on_flush: OnFlush? = nil) -> NostrEvent? {
    let req = make_wallet_pay_invoice_request(invoice: invoice)
    guard let ev = make_wallet_connect_request(req: req, to_pk: url.pubkey, keypair: url.keypair) else {
        return nil
    }

    try? pool.add_relay(.nwc(url: url.relay))
    subscribe_to_nwc(url: url, pool: pool)
    post.send(ev, to: [url.relay], skip_ephemeral: false, delay: delay, on_flush: on_flush)
    return ev
}


func nwc_success(state: DamusState, resp: FullWalletResponse) {
    // find the pending zap and mark it as pending-confirmed
    for kv in state.zaps.our_zaps {
        let zaps = kv.value
        
        for zap in zaps {
            guard case .pending(let pzap) = zap,
                  case .nwc(let nwc_state) = pzap.state,
                  case .postbox_pending(let nwc_req) = nwc_state.state,
                  nwc_req.id == resp.req_id
            else {
                continue
            }
            
            if nwc_state.update_state(state: .confirmed) {
                // notify the zaps model of an update so it can mark them as paid
                state.events.get_cache_data(NoteId(pzap.target.id)).zaps_model.objectWillChange.send()
                print("NWC success confirmed")
            }
            
            return
        }
    }
}

func send_donation_zap(pool: RelayPool, postbox: PostBox, nwc: WalletConnectURL, percent: Int, base_msats: Int64) async {
    let percent_f = Double(percent) / 100.0
    let donations_msats = Int64(percent_f * Double(base_msats))
    
    let payreq = LNUrlPayRequest(allowsNostr: true, commentAllowed: nil, nostrPubkey: "", callback: "https://sendsats.lol/@damus")
    guard let invoice = await fetch_zap_invoice(payreq, zapreq: nil, msats: donations_msats, zap_type: .non_zap, comment: nil) else {
        // we failed... oh well. no donation for us.
        print("damus-donation failed to fetch invoice")
        return
    }
    
    print("damus-donation donating...")
    nwc_pay(url: nwc, pool: pool, post: postbox, invoice: invoice, delay: nil)
}

func nwc_error(zapcache: Zaps, evcache: EventCache, resp: FullWalletResponse) {
    // find a pending zap with the nwc request id associated with this response and remove it
    for kv in zapcache.our_zaps {
        let zaps = kv.value
        
        for zap in zaps {
            guard case .pending(let pzap) = zap,
                  case .nwc(let nwc_state) = pzap.state,
                  case .postbox_pending(let req) = nwc_state.state,
                  req.id == resp.req_id
            else {
                continue
            }
            
            // remove the pending zap if there was an error
            let reqid = ZapRequestId(from_pending: pzap)
            remove_zap(reqid: reqid, zapcache: zapcache, evcache: evcache)
            return
        }
    }
}
