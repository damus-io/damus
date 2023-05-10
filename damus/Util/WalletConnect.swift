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
    
    func to_url() -> URL {
        let urlstr = "nostrwalletconnect://\(pubkey)?relay=\(relay.id)&secret=\(keypair.privkey)"
        return URL(string: urlstr)!
    }
    
    init?(str: String) {
        guard let url = URL(string: str), url.scheme == "nostrwalletconnect",
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
        
        let keypair = FullKeypair(pubkey: our_pk, privkey: secret)
        self = WalletConnectURL(pubkey: pk, relay: relay_url, keypair: keypair)
    }
    
    init(pubkey: String, relay: RelayURL, keypair: FullKeypair) {
        self.pubkey = pubkey
        self.relay = relay
        self.keypair = keypair
    }
}

struct WalletRequest<T: Codable>: Codable {
    let method: String
    let params: T?
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

func nwc_pay(url: WalletConnectURL, pool: RelayPool, post: PostBox, invoice: String) {
    let req = make_wallet_pay_invoice_request(invoice: invoice)
    guard let ev = make_wallet_connect_request(req: req, to_pk: url.pubkey, keypair: url.keypair) else {
        return
    }
    
    try? pool.add_relay(url.relay, info: .ephemeral)
    post.send(ev, to: [url.relay.id], skip_ephemeral: false)
}
