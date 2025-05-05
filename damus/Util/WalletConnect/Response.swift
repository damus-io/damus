//
//  Response.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-03-10.
//

import Combine

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
        
        init(from event: NostrEvent, nwc: WalletConnect.ConnectURL) async throws(InitializationError) {
            guard event.pubkey == nwc.pubkey else { throw .incorrectAuthorPubkey }
            
            guard let referencedNoteId = event.referenced_ids.first else { throw .missingRequestIdReference }

            self.req_id = referencedNoteId
            
            var json = ""
            do {
                json = try NIP04.decryptContent(
                    recipientPrivateKey: nwc.keypair.privkey,
                    senderPubkey: nwc.pubkey,
                    content: event.content,
                    encoding: .base64
                )
            }
            catch { throw .failedToDecrypt(error) }
            
            do {
                let response: WalletConnect.Response = try decode_json_throwing(json)
                self.response = response
            }
            catch { throw .failedToDecodeJSON(error) }
        }
        
        enum InitializationError: Error {
            case incorrectAuthorPubkey
            case missingRequestIdReference
            case failedToDecodeJSON(any Error)
            case failedToDecrypt(any Error)
        }
    }
    
    struct WalletResponseErr: Codable {
        let code: Code?
        let message: String?

        enum Code: String, Codable {
            /// The client is sending commands too fast. It should retry in a few seconds.
            case rateLimited = "RATE_LIMITED"
            /// The command is not known or is intentionally not implemented.
            case notImplemented = "NOT_IMPLEMENTED"
            /// The wallet does not have enough funds to cover a fee reserve or the payment amount.
            case insufficientBalance = "INSUFFICIENT_BALANCE"
            /// The wallet has exceeded its spending quota.
            case quotaExceeded = "QUOTA_EXCEEDED"
            /// This public key is not allowed to do this operation.
            case restricted = "RESTRICTED"
            /// This public key has no wallet connected.
            case unauthorized = "UNAUTHORIZED"
            /// An internal error.
            case internalError = "INTERNAL"
            /// Other error.
            case other = "OTHER"
        }

        enum CodingKeys: String, CodingKey {
            case code, message
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            
            // Attempt to decode the code as a String
            if let codeString = try container.decodeIfPresent(String.self, forKey: .code),
               let validCode = Code(rawValue: codeString) {
                self.code = validCode
            } else {
                // If the code is either missing or not one of the allowed cases, set it to nil
                self.code = nil
            }
            
            self.message = try container.decodeIfPresent(String.self, forKey: .message)
        }
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
