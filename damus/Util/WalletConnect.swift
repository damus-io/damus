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
    let pubkey: Pubkey
    let lud16: String?
    
    func to_url() -> URL {
        var urlComponents = URLComponents()
        urlComponents.scheme = "nostrwalletconnect"
        urlComponents.host = pubkey.hex()
        urlComponents.queryItems = [
            URLQueryItem(name: "relay", value: relay.absoluteString),
            URLQueryItem(name: "secret", value: keypair.privkey.hex())
        ]

        if let lud16 {
            urlComponents.queryItems?.append(URLQueryItem(name: "lud16", value: lud16))
        }

        return urlComponents.url!
    }
    
    init?(str: String) {
        guard let components = URLComponents(string: str),
              components.scheme == "nostrwalletconnect" || components.scheme == "nostr+walletconnect",
              // The line below provides flexibility for both `nostrwalletconnect://` (non-compliant, but commonly used) and `nostrwalletconnect:` (NIP-47 compliant) formats
              let encoded_pubkey = components.path == "" ? components.host : components.path,
              let pubkey = hex_decode_pubkey(encoded_pubkey),
              let items = components.queryItems,
              let relay = items.first(where: { qi in qi.name == "relay" })?.value,
              let relay_url = RelayURL(relay),
              let secret = items.first(where: { qi in qi.name == "secret" })?.value,
              secret.utf8.count == 64,
              let decoded = hex_decode(secret)
        else {
            return nil
        }

        let privkey = Privkey(Data(decoded))
        guard let our_pk = privkey_to_pubkey(privkey: privkey) else { return nil }

        let lud16 = items.first(where: { qi in qi.name == "lud16" })?.value
        let keypair = FullKeypair(pubkey: our_pk, privkey: privkey)
        self = WalletConnectURL(pubkey: pubkey, relay: relay_url, keypair: keypair, lud16: lud16)
    }
    
    init(pubkey: Pubkey, relay: RelayURL, keypair: FullKeypair, lud16: String?) {
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
    let req_id: NoteId
    let response: WalletResponse
    
    init?(from: NostrEvent, nwc: WalletConnectURL) async {
        guard let note_id = from.referenced_ids.first else {
            return nil
        }

        self.req_id = note_id

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

