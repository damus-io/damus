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

// MARK: - Nostr web link conversion

private let bech32Charset = "023456789acdefghjklmnpqrstuvwxyz"

/// note1 excluded: draft classifier misclassifies .note mentions as quotes.
/// nsec1 excluded: handled by `sanitizeNsecTokens`.
private let convertibleNIP19Prefixes = ["nevent1", "npub1", "nprofile1", "naddr1"]
private let allNIP19Prefixes = ["nevent1", "npub1", "nprofile1", "naddr1", "note1", "nsec1"]

/// Scans a URL path for a NIP-19 prefix followed by valid bech32 characters.
private func extractBech32FromURLPath(_ url: URL, prefixes: [String]) -> (prefix: String, candidate: String)? {
    let path = url.path
    for prefix in prefixes {
        guard let prefixRange = path.range(of: prefix) else { continue }
        let startIndex = prefixRange.lowerBound
        var endIndex = prefixRange.upperBound
        while endIndex < path.endIndex {
            let char = path[endIndex]
            if bech32Charset.contains(char) {
                endIndex = path.index(after: endIndex)
            } else {
                break
            }
        }
        let candidate = String(path[startIndex..<endIndex])
        if candidate.count > prefix.count {
            return (prefix, candidate)
        }
    }
    return nil
}

/// Returns the first URL and its parsed `Bech32Object` from text, or nil if none found.
func firstNostrWebLink(_ text: String) -> (url: URL, bech32: Bech32Object)? {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
        return nil
    }
    let nsRange = NSRange(text.startIndex..., in: text)
    for match in detector.matches(in: text, options: [], range: nsRange) {
        guard let url = match.url, url.scheme != "nostr" else { continue }
        guard let (_, candidate) = extractBech32FromURLPath(url, prefixes: allNIP19Prefixes) else { continue }
        guard let parsed = Bech32Object.parse(candidate) else { continue }
        return (url, parsed)
    }
    return nil
}

/// Converts URLs in the given content string that contain NIP-19 bech32 identifiers
/// in their path to the `nostr:{bech32}` format. Only converts identifiers that pass
/// `Bech32Object.parse()` validation. Skips `note1` and `nsec1` prefixes.
///
/// Example: `https://njump.me/nevent1abc...` -> `nostr:nevent1abc...`
func convertNostrWebLinksToNative(_ content: String) -> String {
    guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else {
        return content
    }

    let nsRange = NSRange(content.startIndex..., in: content)
    let matches = detector.matches(in: content, options: [], range: nsRange)

    // Collect replacements, then apply back-to-front to preserve indices
    var replacements: [(NSRange, String)] = []

    for match in matches {
        guard let url = match.url else { continue }
        guard url.scheme != "nostr" else { continue }
        guard let (_, candidate) = extractBech32FromURLPath(url, prefixes: convertibleNIP19Prefixes) else { continue }
        guard Bech32Object.parse(candidate) != nil else { continue }
        replacements.append((match.range, "nostr:\(candidate)"))
    }

    guard !replacements.isEmpty else { return content }

    var result = content
    for (range, replacement) in replacements.reversed() {
        guard let swiftRange = Range(range, in: result) else { continue }
        result.replaceSubrange(swiftRange, with: replacement)
    }
    return result
}

// MARK: - nsec sanitization

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
