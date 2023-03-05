//
//  WalletConnect.swift
//  damus
//
//  Created by William Casarin on 2023-03-22.
//

import Foundation

struct WalletConnectURL: Equatable {
    static func == (lhs: WalletConnectURL, rhs: WalletConnectURL) -> Bool {
        return lhs.keypair == rhs.keypair &&
                lhs.pubkey == rhs.pubkey &&
                lhs.relay == rhs.relay
    }
    
    let relay: RelayURL
    let keypair: FullKeypair
    let pubkey: String
    let lud16: String?
    
    func to_url() -> URL {
        var urlComponents = URLComponents()
        urlComponents.scheme = "nostrwalletconnect"
        urlComponents.host = pubkey
        urlComponents.queryItems = [
            URLQueryItem(name: "relay", value: relay.id),
            URLQueryItem(name: "secret", value: keypair.privkey)
        ]

        if let lud16 {
            urlComponents.queryItems?.append(URLQueryItem(name: "lud16", value: lud16))
        }

        return urlComponents.url!
    }
    
    init?(str: String) {
        guard let url = URL(string: str),
              url.scheme == "nostrwalletconnect" || url.scheme == "nostr+walletconnect",
              let pk = url.host, pk.utf8.count == 64,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let items = components.queryItems,
              let relay = items.first(where: { qi in qi.name == "relay" })?.value,
              let relay_url = RelayURL(relay),
              let secret = items.first(where: { qi in qi.name == "secret" })?.value,
              secret.utf8.count == 64,
              let our_pk = privkey_to_pubkey(privkey: secret)
        else {
            return nil
        }
        
        let lud16 = items.first(where: { qi in qi.name == "lud16" })?.value
        let keypair = FullKeypair(pubkey: our_pk, privkey: secret)
        self = WalletConnectURL(pubkey: pk, relay: relay_url, keypair: keypair, lud16: lud16)
    }
    
    init(pubkey: String, relay: RelayURL, keypair: FullKeypair, lud16: String?) {
        self.pubkey = pubkey
        self.relay = relay
        self.keypair = keypair
        self.lud16 = lud16
    }
}

struct WalletRequest<T: Codable>: Codable {
    let method: String
    let params: T?
}

struct WalletResponseErr: Codable {
    let code: String?
    let message: String?
}

struct PayInvoiceResponse: Decodable {
    let preimage: String
}

enum WalletResponseResultType: String {
    case pay_invoice
}

enum WalletResponseResult {
    case pay_invoice(PayInvoiceResponse)
}

struct FullWalletResponse {
    let req_id: String
    let response: WalletResponse
    
    init?(from: NostrEvent, nwc: WalletConnectURL) async {
        guard let req_id = from.referenced_ids.first else {
            return nil
        }
        
        self.req_id = req_id.ref_id
        
        let ares = Task {
            guard let json = decrypt_dm(nwc.keypair.privkey, pubkey: nwc.pubkey, content: from.content, encoding: .base64),
                  let resp: WalletResponse = decode_json(json)
            else {
                let resp: WalletResponse? = nil
                return resp
            }
            
            return resp
        }
        
        guard let res = await ares.value else {
            return nil
        }
            
        self.response = res
    }
    
}

struct WalletResponse: Decodable {
    let result_type: WalletResponseResultType
    let error: WalletResponseErr?
    let result: WalletResponseResult?
    
    private enum CodingKeys: CodingKey {
        case result_type, error, result
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let result_type_str = try container.decode(String.self, forKey: .result_type)
        
        guard let result_type = WalletResponseResultType(rawValue: result_type_str) else {
            throw DecodingError.typeMismatch(WalletResponseResultType.self, .init(codingPath: decoder.codingPath, debugDescription: "result_type \(result_type_str) is unknown"))
        }
        
        self.result_type = result_type
        self.error = try container.decodeIfPresent(WalletResponseErr.self, forKey: .error)
        
        guard self.error == nil else {
            self.result = nil
            return
        }
        
        switch result_type {
        case .pay_invoice:
            let res = try container.decode(PayInvoiceResponse.self, forKey: .result)
            self.result = .pay_invoice(res)
        }
    }
}

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

func make_wallet_connect_request<T>(req: WalletRequest<T>, to_pk: String, keypair: FullKeypair) -> NostrEvent? {
    let tags = [["p", to_pk]]
    let created_at = Int64(Date().timeIntervalSince1970)
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
    
    pool.send(.subscribe(sub), to: [url.relay.id], skip_ephemeral: false)
}

@discardableResult
func nwc_pay(url: WalletConnectURL, pool: RelayPool, post: PostBox, invoice: String, delay: TimeInterval? = 5.0, on_flush: OnFlush? = nil) -> NostrEvent? {
    let req = make_wallet_pay_invoice_request(invoice: invoice)
    guard let ev = make_wallet_connect_request(req: req, to_pk: url.pubkey, keypair: url.keypair) else {
        return nil
    }
    
    try? pool.add_relay(.nwc(url: url.relay))
    subscribe_to_nwc(url: url, pool: pool)
    post.send(ev, to: [url.relay.id], skip_ephemeral: false, delay: delay, on_flush: on_flush)
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
                state.events.get_cache_data(pzap.target.id).zaps_model.objectWillChange.send()
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
