//
//  AdvancedSearchConstraint.swift
//  damus
//
//  Created by William Casarin on 2026-09-02.
//

import Foundation

/// One removable piece of an ``AdvancedSearchQuery``.
///
/// This exists so a narrowed search is understandable when it comes back with
/// little: the results view lists these as chips, and tapping one takes that
/// single constraint off rather than making the user retype the query. A search
/// that returns nothing because of a date window nobody can see is the worst
/// outcome this feature has.
///
/// Only constraints that are actually *doing* something appear —
/// ``all(in:)`` skips the default kind set and the default order, so a plain
/// keyword search shows one chip per word and nothing else.
enum AdvancedSearchConstraint: Equatable, Identifiable {
    case author(Pubkey)
    case keyword(String)
    case phrase(String)
    case hashtag(String)
    case since(Date)
    case until(Date)
    /// The content-type narrowing, present only when it is not the default set.
    case kinds(Set<NostrKind>)
    /// Present only when it is not the default newest-first.
    case order(NdbSearchOrder)

    /// Every constraint `query` is carrying, in the order they read best: who,
    /// when, then what.
    static func all(in query: AdvancedSearchQuery) -> [AdvancedSearchConstraint] {
        var constraints: [AdvancedSearchConstraint] = query.authors.map({ .author($0) })
        if let since = query.since { constraints.append(.since(since)) }
        if let until = query.until { constraints.append(.until(until)) }
        if query.kinds != AdvancedSearchQuery.defaultKinds { constraints.append(.kinds(query.kinds)) }
        if query.order != .newest_first { constraints.append(.order(query.order)) }
        constraints += query.hashtags.map({ .hashtag($0) })
        constraints += query.phrases.map({ .phrase($0) })
        constraints += query.keywords.map({ .keyword($0) })
        return constraints
    }

    /// `query` without this constraint.
    ///
    /// Removing a constraint restores the default rather than leaving a hole:
    /// dropping the kind chip restores all indexed content types.
    func removed(from query: AdvancedSearchQuery) -> AdvancedSearchQuery {
        var query = query
        switch self {
        case .author(let pubkey): query.authors.removeAll(where: { $0 == pubkey })
        case .keyword(let keyword): query.keywords.removeAll(where: { $0 == keyword })
        case .phrase(let phrase): query.phrases.removeAll(where: { $0 == phrase })
        case .hashtag(let hashtag): query.hashtags.removeAll(where: { $0 == hashtag })
        case .since: query.since = nil
        case .until: query.until = nil
        case .kinds: query.kinds = AdvancedSearchQuery.defaultKinds
        case .order: query.order = .newest_first
        }
        return query
    }

    /// How the chip reads.
    ///
    /// - Parameter authorName: Turns a pubkey into something a person recognises.
    ///   The caller owns this because only it has the profile index.
    func label(authorName: (Pubkey) -> String) -> String {
        switch self {
        case .author(let pubkey):
            return String(format: NSLocalizedString("from: %@", comment: "Search filter chip naming the author whose notes are being searched."),
                          authorName(pubkey))
        case .keyword(let keyword):
            return keyword
        case .phrase(let phrase):
            return "\u{201C}\(phrase)\u{201D}"
        case .hashtag(let hashtag):
            return "#\(hashtag)"
        case .since(let date):
            return String(format: NSLocalizedString("since %@", comment: "Search filter chip naming the earliest date included in the search."),
                          date.formatted(date: .abbreviated, time: .omitted))
        case .until(let date):
            return String(format: NSLocalizedString("until %@", comment: "Search filter chip naming the latest date included in the search."),
                          date.formatted(date: .abbreviated, time: .omitted))
        case .kinds(let kinds):
            if kinds == [.text] {
                return NSLocalizedString("notes only", comment: "Search filter chip indicating only short text notes are being searched.")
            } else if kinds == [.voice] {
                return NSLocalizedString("voice only", comment: "Search filter chip indicating only voice transcripts are being searched.")
            } else if kinds == [.longform] {
                return NSLocalizedString("long-form only", comment: "Search filter chip indicating only long-form articles are being searched.")
            }
            return NSLocalizedString("selected content types", comment: "Search filter chip indicating a custom set of content types is being searched.")
        case .order(let order):
            switch order {
            case .oldest_first:
                return NSLocalizedString("oldest first", comment: "Search filter chip indicating results are ordered oldest first.")
            case .newest_first:
                return NSLocalizedString("newest first", comment: "Search filter chip indicating results are ordered newest first.")
            }
        }
    }

    /// True when this constraint narrows *where* the search looks rather than
    /// *what* it looks for.
    ///
    /// These are what the filter badge counts. A keyword or phrase is already
    /// visible in the search field, but an author or a date window is not, and an
    /// invisible narrowing is what makes an empty result look like an answer.
    var isFilter: Bool {
        switch self {
        case .keyword, .phrase: return false
        case .author, .hashtag, .since, .until, .kinds, .order: return true
        }
    }

    var id: String {
        switch self {
        case .author(let pubkey): return "author:\(pubkey.hex())"
        case .keyword(let keyword): return "keyword:\(keyword)"
        case .phrase(let phrase): return "phrase:\(phrase)"
        case .hashtag(let hashtag): return "hashtag:\(hashtag)"
        case .since(let date): return "since:\(date.timeIntervalSince1970)"
        case .until(let date): return "until:\(date.timeIntervalSince1970)"
        case .kinds(let kinds): return "kinds:\(kinds.map(\.rawValue).sorted())"
        case .order(let order): return "order:\(order == .newest_first ? "newest" : "oldest")"
        }
    }
}
