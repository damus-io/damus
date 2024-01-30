//
//  URIParsing.swift
//  damus
//
//  Created by KernelKind on 1/13/24.
//

import Foundation

fileprivate let MAX_CHAR_URL = 80

private func remove_damus_uri_prefix(_ s: String) -> String {
    var uri = s.replacingOccurrences(of: "https://damus.io/r/", with: "")
    uri = uri.replacingOccurrences(of: "https://damus.io/", with: "")
    uri = uri.replacingOccurrences(of: "/", with: "")
    
    return uri
}

func remove_nostr_uri_prefix(_ s: String) -> String {
    if s.starts(with: "https://damus.io/") {
        return remove_damus_uri_prefix(s)
    }

    var uri = s
    uri = uri.replacingOccurrences(of: "nostr://", with: "")
    uri = uri.replacingOccurrences(of: "nostr:", with: "")

    // Fix for non-latin characters resulting in second colon being encoded
    uri = uri.replacingOccurrences(of: "damus:t%3A", with: "t:")
    
    uri = uri.replacingOccurrences(of: "damus://", with: "")
    uri = uri.replacingOccurrences(of: "damus:", with: "")
    
    return uri
}

func abbreviateURL(_ url: URL) -> String {
    let urlString = url.absoluteString
    
    if urlString.count > MAX_CHAR_URL {
        return String(urlString.prefix(MAX_CHAR_URL)) + "..."
    }
    return urlString
}
