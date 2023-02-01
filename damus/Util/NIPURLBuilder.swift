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
        let urlString: String
        if nip < 10 {
            urlString = baseURL + "0\(nip).md"
        } else {
            urlString = baseURL + "\(nip).md"
        }
        return URL(string: urlString)
    }
}
