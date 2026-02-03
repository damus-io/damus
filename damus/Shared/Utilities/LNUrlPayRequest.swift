//
//  LNUrl.swift
//  damus
//
//  Created by William Casarin on 2023-01-16.
//

import Foundation

/// Represents an LNURL pay request payload returned by a remote endpoint.
struct LNUrlPayRequest: Decodable, Sendable {
    let allowsNostr: Bool?
    let commentAllowed: Int?
    let nostrPubkey: String?
    
    let callback: String?
}



/// Represents an LNURL pay response containing the payment request (invoice).
struct LNUrlPayResponse: Decodable, Sendable {
    let pr: String
}
