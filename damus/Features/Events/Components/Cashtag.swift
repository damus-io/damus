//
//  Cashtag.swift
//  damus
//
//  Cashtag detection: `$BTC`, `$ETH` etc. Parsed Swift-side from the
//  note's raw content so nostrdb's block parser is untouched.
//

import Foundation

/// A ticker symbol referenced in a note via a leading `$`, e.g. `$BTC`.
struct Cashtag: Hashable {
    /// Upper-cased ticker without the `$`, e.g. "BTC".
    let symbol: String

    /// Matches `$` followed by 2–6 uppercase letters, bounded by non-word
    /// characters so `US$100` or `$btcx1` are ignored.
    private static let regex = try! NSRegularExpression(pattern: #"(?<![\w$])\$([A-Z]{2,6})(?![\w$])"#)

    /// Extracts unique cashtags from `content`, in order of first appearance.
    ///
    /// - Parameter content: Raw note text.
    /// - Returns: Deduplicated cashtags, or an empty array if none.
    static func extract(from content: String) -> [Cashtag] {
        let range = NSRange(content.startIndex..., in: content)
        var seen = Set<String>()
        var result: [Cashtag] = []

        for match in regex.matches(in: content, range: range) {
            guard let r = Range(match.range(at: 1), in: content) else { continue }
            let symbol = String(content[r])
            guard seen.insert(symbol).inserted else { continue }
            result.append(Cashtag(symbol: symbol))
        }
        return result
    }
}
