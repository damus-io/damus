//
//  Request.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-03-10.
//

import Foundation

extension WalletConnect {
    /// Models a request to an NWC wallet provider
    enum Request: Codable {
        /// Pay an invoice
        case payInvoice(
            /// bolt-11 invoice string
            invoice: String,
            /// The full description of the invoice (If description does not fit in the BOLT-11 invoice, this is the pre-image of the description hash)
            description: String?,
            /// Optional metadata object containing more information
            metadata: Metadata?
        )
        /// Get the current wallet balance
        case getBalance
        /// Get the current wallet transaction history
        case getTransactionList(
            /// Starting timestamp in seconds since epoch (inclusive), optional.
            from: UInt64?,
            /// Ending timestamp in seconds since epoch (inclusive), optional.
            until: UInt64?,
            /// Maximum number of invoices to return, optional.
            limit: Int?,
            /// Offset of the first invoice to return, optional.
            offset: Int?,
            /// Include unpaid invoices, optional, default false.
            unpaid: Bool?,
            /// "incoming" for invoices, "outgoing" for payments, undefined for both.
            type: String?
        )
        
        static func payZapRequest(invoice: String, zapRequest: NostrEvent?) -> Self {
            guard let zapRequest, let zapRequestEncoded = encode_json(zapRequest) else {
                return WalletConnect.Request.payInvoice(
                    invoice: invoice,
                    description: nil,
                    metadata: nil
                )
            }
            return WalletConnect.Request.payInvoice(
                invoice: invoice,
                description: zapRequestEncoded,
                metadata: .init(nostr: zapRequest)
            )
        }
        
        struct Metadata: Codable, Equatable, Hashable {
            /// NIP-57-compliant `kind:9734` zap request event
            let nostr: NostrEvent?
            
            init(nostr: NostrEvent?) {
                self.nostr = nostr
            }
            
            init(from decoder: any Decoder) throws {
                let container: KeyedDecodingContainer<WalletConnect.Request.Metadata.CodingKeys> = try decoder.container(keyedBy: WalletConnect.Request.Metadata.CodingKeys.self)
                guard let decodedZapRequest = try? container.decodeIfPresent(NostrEvent.self, forKey: WalletConnect.Request.Metadata.CodingKeys.nostr) else {
                    self.nostr = nil    // Be lenient and fallback to nil if the NWC provider provided something invalid, since metadata is not strictly spec'd yet.
                    return
                }
                self.nostr = decodedZapRequest
            }
        }
        
        // MARK: - Interface
        
        /// Converts the NWC request into a raw Nostr event to be sent in the network
        ///
        /// - Parameters:
        ///   - to_pk: The destination pubkey (used for encryption)
        ///   - keypair: The requester's pubkey (used for encryption and signing)
        /// - Returns: The NWC request in a raw Nostr Event format, or nil if it cannot be encoded
        func to_nostr_event(to_pk: Pubkey, keypair: FullKeypair) -> NostrEvent? {
            let tags = [to_pk.tag]
            let created_at = UInt32(Date().timeIntervalSince1970)
            guard let content = encode_json(self) else {
                return nil
            }
            return NIP04.create_encrypted_event(content, to_pk: to_pk, tags: tags, keypair: keypair, created_at: created_at, kind: NostrKind.nwc_request.rawValue)
        }
        
        // MARK: - Encoding and decoding
        
        /// Keys for top-level JSON
        private enum CodingKeys: String, CodingKey {
            case method
            case params
        }
        
        /// Keys for the JSON inside the "params" object
        private enum ParamKeys: String, CodingKey {
            case invoice, description, metadata
            case from, until, limit, offset, unpaid, type
        }
        
        /// Constants for possible request "method" verbs
        private enum Method: String {
            case payInvoice = "pay_invoice"
            case getBalance = "get_balance"
            case listTransactions = "list_transactions"
        }
        
        /// Decodes a payload into this request structure
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let method = try container.decode(String.self, forKey: .method)
            
            
            switch method {
            case Method.payInvoice.rawValue:
                let paramsContainer = try container.nestedContainer(keyedBy: ParamKeys.self, forKey: .params)
                let invoice = try paramsContainer.decode(String.self, forKey: .invoice)
                let description: String? = try paramsContainer.decodeIfPresent(String.self, forKey: .description)
                let metadata: Metadata? = try paramsContainer.decodeIfPresent(Metadata.self, forKey: .metadata)
                self = .payInvoice(invoice: invoice, description: description, metadata: metadata)
                
            case Method.getBalance.rawValue:
                // No params to decode
                self = .getBalance
                
            case Method.listTransactions.rawValue:
                let paramsContainer = try container.nestedContainer(keyedBy: ParamKeys.self, forKey: .params)
                let from = try paramsContainer.decodeIfPresent(UInt64.self, forKey: .from)
                let until = try paramsContainer.decodeIfPresent(UInt64.self, forKey: .until)
                let limit = try paramsContainer.decodeIfPresent(Int.self, forKey: .limit)
                let offset = try paramsContainer.decodeIfPresent(Int.self, forKey: .offset)
                let unpaid = try paramsContainer.decodeIfPresent(Bool.self, forKey: .unpaid)
                let type = try paramsContainer.decodeIfPresent(String.self, forKey: .type)
                self = .getTransactionList(from: from, until: until, limit: limit, offset: offset, unpaid: unpaid, type: type)
                
            default:
                throw DecodingError.dataCorruptedError(
                    forKey: .method,
                    in: container,
                    debugDescription: "Unknown wallet method \"\(method)\""
                )
            }
        }
        
        /// Encodes this request structure into a payload
        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            
            switch self {
            case .payInvoice(let invoice, let description, let metadata):
                try container.encode(Method.payInvoice.rawValue, forKey: .method)
                var paramsContainer = container.nestedContainer(keyedBy: ParamKeys.self, forKey: .params)
                try paramsContainer.encode(invoice, forKey: .invoice)
                try paramsContainer.encodeIfPresent(description, forKey: .description)
                try paramsContainer.encodeIfPresent(metadata, forKey: .metadata)
                
            case .getBalance:
                try container.encode(Method.getBalance.rawValue, forKey: .method)
                // "params": null
                try container.encodeNil(forKey: .params)
                
            case .getTransactionList(let from, let until, let limit, let offset, let unpaid, let type):
                try container.encode(Method.listTransactions.rawValue, forKey: .method)
                var paramsContainer = container.nestedContainer(keyedBy: ParamKeys.self, forKey: .params)
                try paramsContainer.encodeIfPresent(from, forKey: .from)
                try paramsContainer.encodeIfPresent(until, forKey: .until)
                try paramsContainer.encodeIfPresent(limit, forKey: .limit)
                try paramsContainer.encodeIfPresent(offset, forKey: .offset)
                try paramsContainer.encodeIfPresent(unpaid, forKey: .unpaid)
                try paramsContainer.encodeIfPresent(type, forKey: .type)
            }
        }
    }
}
