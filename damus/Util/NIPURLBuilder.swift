//
//  NIPURLBuilder.swift
//  damus
//
//  Created by Honk on 2/1/23.
//

import Foundation

struct NIPURLBuilder {
    static private let baseURL = "https://github.com/nostr-protocol/nips/blob/master/"
    static func url(forNIP nip: Int) -> URL? {
        let urlString = baseURL + "\(formatNipNumber(nip: nip)).md"
        return URL(string: urlString)
    }
    
    static func formatNipNumber(nip: Int) -> String {
        let formatted: String
        if nip < 10 {
            formatted = "0\(nip)"
        } else {
            formatted = "\(nip)"
        }
        return formatted
    }
}
