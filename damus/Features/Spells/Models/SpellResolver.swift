//
//  SpellResolver.swift
//  damus
//
//  Resolves a SpellEvent's runtime variables and relative timestamps
//  into concrete NostrFilter(s) ready for relay subscription.
//

import Foundation

/// The context needed to resolve a spell's runtime variables.
struct SpellResolutionContext {
    let userPubkey: Pubkey
    let contacts: [Pubkey]
    let now: UInt64
}

/// A fully resolved spell ready for subscription.
///
/// Carries both NdbFilter (for local nostrdb queries) and NostrFilter
/// (for relay JSON serialization). NdbFilter is the primary query type.
struct ResolvedSpell {
    let spell: SpellEvent
    let ndbFilters: [NdbFilter]
    let filters: [NostrFilter]
    let command: SpellCommand
    let relays: [String]
    let closeOnEose: Bool
    let search: String?
}

enum SpellResolutionError: Error, Equatable {
    /// $contacts was used but no contacts are available
    case emptyContacts
    /// No filter could be built from the spell
    case emptyFilter
    /// NostrFilter could not be converted to NdbFilter
    case filterConversionFailed
}

private let SPELL_MAX_AUTHORS_PER_FILTER = 500

/// Resolves a parsed SpellEvent into concrete NostrFilter(s).
struct SpellResolver {

    /// Resolve a spell using the given context.
    ///
    /// Variables like `$me` and `$contacts` are replaced with concrete pubkeys,
    /// and relative timestamps are converted to absolute Unix timestamps.
    /// Returns chunked filters if the author list exceeds the limit.
    static func resolve(_ spell: SpellEvent, context: SpellResolutionContext) -> Result<ResolvedSpell, SpellResolutionError> {
        // Check contacts requirement
        if spell.requiresContacts && context.contacts.isEmpty {
            return .failure(.emptyContacts)
        }

        var filter = NostrFilter()

        // Kinds
        if !spell.kinds.isEmpty {
            filter.kinds = spell.kinds.compactMap { NostrKind(rawValue: $0) }
            if filter.kinds?.isEmpty ?? true {
                filter.kinds = nil
            }
        }

        // Authors: resolve $me and $contacts to pubkeys
        let resolvedAuthors = resolvePubkeys(spell.authors, context: context)
        if !resolvedAuthors.isEmpty {
            filter.authors = resolvedAuthors
        }

        // IDs
        if !spell.ids.isEmpty {
            filter.ids = spell.ids.compactMap { NoteId(hex: $0) }
        }

        // Tag filters: map known letters to NostrFilter fields
        for tagFilter in spell.tagFilters {
            switch tagFilter.letter {
            case "t":
                filter.hashtag = resolveLiteralStrings(tagFilter.values)
            case "p":
                filter.pubkeys = resolvePubkeys(tagFilter.values, context: context)
            case "e":
                filter.referenced_ids = resolveLiteralStrings(tagFilter.values)
                    .compactMap { NoteId(hex: $0) }
            case "d":
                filter.parameter = resolveLiteralStrings(tagFilter.values)
            case "q":
                filter.quotes = resolveLiteralStrings(tagFilter.values)
                    .compactMap { NoteId(hex: $0) }
            default:
                break
            }
        }

        // Limit
        filter.limit = spell.limit

        // Since
        if let since = spell.since {
            filter.since = UInt32(since.resolve(now: context.now))
        }

        // Until
        if let until = spell.until {
            filter.until = UInt32(until.resolve(now: context.now))
        }

        // Chunk large author lists
        let filters: [NostrFilter]
        if let authors = filter.authors, authors.count > SPELL_MAX_AUTHORS_PER_FILTER {
            filters = filter.chunked(on: .authors, into: SPELL_MAX_AUTHORS_PER_FILTER)
        } else {
            filters = [filter]
        }

        guard !filters.isEmpty else {
            return .failure(.emptyFilter)
        }

        // Eagerly convert to NdbFilter for local nostrdb queries.
        // Failing early here surfaces filter issues at resolution time.
        let ndbFilters: [NdbFilter]
        do {
            ndbFilters = try filters.toNdbFilters()
        } catch {
            return .failure(.filterConversionFailed)
        }

        let resolved = ResolvedSpell(
            spell: spell,
            ndbFilters: ndbFilters,
            filters: filters,
            command: spell.command,
            relays: spell.relays,
            closeOnEose: spell.closeOnEose,
            search: spell.search
        )
        return .success(resolved)
    }

    // MARK: - Private

    /// Resolve SpellValues to pubkeys, expanding $me and $contacts.
    private static func resolvePubkeys(_ values: [SpellValue], context: SpellResolutionContext) -> [Pubkey] {
        var result: [Pubkey] = []
        for value in values {
            switch value {
            case .literal(let hex):
                if let pubkey = Pubkey(hex: hex) {
                    result.append(pubkey)
                }
            case .variable(let variable):
                switch variable {
                case .me:
                    result.append(context.userPubkey)
                case .contacts:
                    result.append(contentsOf: context.contacts)
                }
            }
        }
        return result
    }

    /// Extract literal string values, skipping variables (used for hashtags, parameters).
    private static func resolveLiteralStrings(_ values: [SpellValue]) -> [String] {
        return values.compactMap { value in
            switch value {
            case .literal(let str): return str
            case .variable: return nil
            }
        }
    }
}
