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

func abbreviateURL(_ url: URL, maxLength: Int = MAX_CHAR_URL) -> String {
    let urlString = url.absoluteString

    if urlString.count > maxLength {
        return String(urlString.prefix(maxLength)) + "…"
    }
    return urlString
}

// MARK: - nsec sanitization

private let bech32Charset = "023456789acdefghjklmnpqrstuvwxyz"

private let nsecPattern = "\\bnsec1[\(bech32Charset)]{58,}\\b"

/// Strips validated nsec1 tokens from the content string to prevent accidental private key leakage.
/// Only strips tokens that pass `Bech32Object.parse()` validation (which returns `.npub` for valid nsec1).
func sanitizeNsecTokens(_ content: String) -> String {
    guard let regex = try? NSRegularExpression(pattern: nsecPattern, options: []) else {
        return content
    }

    let nsRange = NSRange(content.startIndex..., in: content)
    let matches = regex.matches(in: content, options: [], range: nsRange)

    guard !matches.isEmpty else { return content }

    var result = content
    for match in matches.reversed() {
        guard let swiftRange = Range(match.range, in: result) else { continue }
        let candidate = String(result[swiftRange])
        // Bech32Object.parse returns .npub for valid nsec1 (never .nsec)
        guard Bech32Object.parse(candidate) != nil else { continue }
        result.replaceSubrange(swiftRange, with: "")
    }

    // Clean up any multiple spaces left behind
    result = result.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)

    return result.trimmingCharacters(in: .whitespaces)
}
