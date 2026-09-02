//
//  SearchContentMatcher.swift
//  damus
//
//  Created by William Casarin on 2026-09-01.
//

import Foundation

/// Decides whether a note's content really matches the term half of an
/// ``AdvancedSearchQuery``.
///
/// nostrdb's indices produce *candidates*; this produces the answer. Both search
/// strategies run every candidate through it, so switching strategies never
/// changes what matches — which is what lets the global strategy hand nostrdb a
/// deliberately loose probe and narrow the results back here.
///
/// The rules:
///
/// - **Keywords** match at a word boundary, and may match a prefix of a word:
///   "art" matches "art" and "artist" but not "start". That mirrors nostrdb's own
///   index matching (`ndb_prefix_matches`, `nostrdb/src/nostrdb.c:6323`), which
///   is a prefix range search, so the two agree.
/// - **Phrases** are plain substring matches for now. Real exact-phrase
///   semantics are Phase 3.
/// - Both are case- and diacritic-insensitive.
/// - Every keyword and every phrase must match: it is an AND, not an OR.
struct SearchContentMatcher: Equatable {
    /// Folded, so `matches(_:)` only has to fold the note.
    private let keywords: [String]
    private let phrases: [String]

    init(keywords: [String], phrases: [String]) {
        self.keywords = keywords.map(Self.folded).filter({ !$0.isEmpty })
        self.phrases = phrases.map(Self.folded).filter({ !$0.isEmpty })
    }

    init(query: AdvancedSearchQuery) {
        self.init(keywords: query.keywords, phrases: query.phrases)
    }

    /// True when there is nothing to match, in which case ``matches(_:)`` accepts
    /// everything and the caller can skip opening notes altogether.
    var isEmpty: Bool { keywords.isEmpty && phrases.isEmpty }

    func matches(_ content: String) -> Bool {
        guard !isEmpty else { return true }

        let folded = Self.folded(content)

        for phrase in phrases {
            guard folded.contains(phrase) else { return false }
        }

        guard !keywords.isEmpty else { return true }
        return Self.containsEveryKeyword(keywords, in: folded)
    }

    /// True when every keyword prefixes some word of `folded`.
    private static func containsEveryKeyword(_ keywords: [String], in folded: String) -> Bool {
        var unmatched = keywords
        for word in folded.split(whereSeparator: { !$0.isLetter && !$0.isNumber }) {
            unmatched.removeAll(where: { word.hasPrefix($0) })
            if unmatched.isEmpty { return true }
        }
        return false
    }

    /// Case, diacritic and width folding, so "Café" and "cafe" match each other.
    ///
    /// - Note: nostrdb's index is byte-wise `tolower` only (`lowercase_strncpy`,
    ///   `nostrdb/src/nostrdb.c:842`) and does no diacritic folding. The global
    ///   strategy can only fold what the index already handed it, so
    ///   diacritic-insensitive matching is fully effective only on the
    ///   author-scoped strategy, which sees every candidate note.
    static func folded(_ string: String) -> String {
        string.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
    }
}
