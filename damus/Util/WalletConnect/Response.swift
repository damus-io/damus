//
//  Response.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-03-10.
//

extension WalletConnect {
    /// Models a response from the NWC provider
    struct Response: Decodable {
        let result_type: Response.Result.ResultType
        let error: WalletResponseErr?
        let result: Response.Result?
        
        private enum CodingKeys: CodingKey {
            case result_type, error, result
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let result_type_str = try container.decode(String.self, forKey: .result_type)
            
            guard let result_type = Response.Result.ResultType(rawValue: result_type_str) else {
                throw DecodingError.typeMismatch(Response.Result.ResultType.self, .init(codingPath: decoder.codingPath, debugDescription: "result_type \(result_type_str) is unknown"))
            }
            
            self.result_type = result_type
            self.error = try container.decodeIfPresent(WalletResponseErr.self, forKey: .error)
            
            guard self.error == nil else {
                self.result = nil
                return
            }
            
            switch result_type {
            case .pay_invoice:
                let res = try container.decode(Result.PayInvoiceResponse.self, forKey: .result)
                self.result = .pay_invoice(res)
            case .get_balance:
                let res = try container.decode(Result.GetBalanceResponse.self, forKey: .result)
                self.result = .get_balance(res)
            case .list_transactions:
                let res = try container.decode(Result.ListTransactionsResponse.self, forKey: .result)
                self.result = .list_transactions(res)
            }
        }
    }
    
    struct FullWalletResponse {
        let req_id: NoteId
        let response: Response
        
        init?(from: NostrEvent, nwc: WalletConnect.ConnectURL) async {
            guard let note_id = from.referenced_ids.first else {
                return nil
            }

            self.req_id = note_id

            let ares = Task {
                guard let json = decrypt_dm(nwc.keypair.privkey, pubkey: nwc.pubkey, content: from.content, encoding: .base64),
                      let resp: WalletConnect.Response = decode_json(json)
                else {
                    let resp: WalletConnect.Response? = nil
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
    
    struct WalletResponseErr: Codable {
        let code: String?
        let message: String?
    }
}

extension WalletConnect.Response {
    /// The response data resulting from an NWC request
    enum Result {
        case pay_invoice(PayInvoiceResponse)
        case get_balance(GetBalanceResponse)
        case list_transactions(ListTransactionsResponse)
        
        enum ResultType: String {
            case pay_invoice
            case get_balance
            case list_transactions
        }
        
        struct PayInvoiceResponse: Decodable {
            let preimage: String
        }

        struct GetBalanceResponse: Decodable {
            let balance: Int64
        }

        struct ListTransactionsResponse: Decodable {
            let transactions: [WalletConnect.Transaction]
        }
    }
}
