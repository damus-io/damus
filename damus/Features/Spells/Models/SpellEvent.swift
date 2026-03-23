//
//  SpellEvent.swift
//  damus
//
//  Created for NIP-A7 spell support (kind:777)
//

import Foundation

/// A runtime variable in a spell that resolves to user-specific values at execution time.
enum SpellVariable: Equatable {
    /// Resolves to the executing user's pubkey
    case me
    /// Resolves to all pubkeys from the executing user's kind:3 contact list
    case contacts

    static func parse(_ value: String) -> SpellVariable? {
        switch value {
        case "$me": return .me
        case "$contacts": return .contacts
        default: return nil
        }
    }

    var displayName: String {
        switch self {
        case .me: return "me"
        case .contacts: return "people I follow"
        }
    }
}

/// A value that may be a literal string or a runtime variable.
enum SpellValue: Equatable {
    case literal(String)
    case variable(SpellVariable)

    static func parse(_ value: String) -> SpellValue {
        if let variable = SpellVariable.parse(value) {
            return .variable(variable)
        }
        return .literal(value)
    }

    var isVariable: Bool {
        if case .variable = self { return true }
        return false
    }
}

/// A timestamp value that may be absolute or relative.
enum SpellTimestamp: Equatable {
    case absolute(UInt64)
    case relative(RelativeTime)
    case now

    struct RelativeTime: Equatable {
        let amount: UInt64
        let unit: Unit

        enum Unit: String, CaseIterable {
            case seconds = "s"
            case minutes = "m"
            case hours = "h"
            case days = "d"
            case weeks = "w"
            case months = "mo"
            case years = "y"

            var secondsMultiplier: UInt64 {
                switch self {
                case .seconds: return 1
                case .minutes: return 60
                case .hours: return 3600
                case .days: return 86400
                case .weeks: return 604800
                case .months: return 2592000
                case .years: return 31536000
                }
            }
        }

        var totalSeconds: UInt64 {
            amount * unit.secondsMultiplier
        }
    }

    static func parse(_ value: String) -> SpellTimestamp? {
        if value == "now" {
            return .now
        }

        if let absolute = UInt64(value) {
            return .absolute(absolute)
        }

        // Parse relative: digits followed by unit (check "mo" before "m")
        for unit in [RelativeTime.Unit.months, .minutes, .seconds, .hours, .days, .weeks, .years] {
            let suffix = unit.rawValue
            if value.hasSuffix(suffix) {
                let numberPart = String(value.dropLast(suffix.count))
                if let amount = UInt64(numberPart), amount > 0 {
                    return .relative(RelativeTime(amount: amount, unit: unit))
                }
            }
        }

        return nil
    }

    /// Resolve to an absolute Unix timestamp.
    func resolve(now: UInt64) -> UInt64 {
        switch self {
        case .absolute(let ts): return ts
        case .now: return now
        case .relative(let rel): return now - rel.totalSeconds
        }
    }
}

/// The command type of a spell.
enum SpellCommand: String, Equatable {
    case req = "REQ"
    case count = "COUNT"
}

/// A tag filter condition from a spell: `["tag", <letter>, <values...>]`
struct SpellTagFilter: Equatable {
    let letter: String
    let values: [SpellValue]
}

/// A parsed kind:777 spell event (NIP-A7).
///
/// Represents the unresolved spell definition — variables and relative timestamps
/// are stored symbolically and resolved at execution time.
struct SpellEvent: Equatable {
    let event: NostrEvent

    // Required
    var command: SpellCommand = .req

    // Filter tags (unresolved)
    var kinds: [UInt32] = []
    var authors: [SpellValue] = []
    var ids: [String] = []
    var tagFilters: [SpellTagFilter] = []
    var limit: UInt32?
    var since: SpellTimestamp?
    var until: SpellTimestamp?
    var search: String?
    var relays: [String] = []

    // Metadata
    var name: String?
    var alt: String?
    var topics: [String] = []
    var closeOnEose: Bool = false
    var forkOf: NoteId?

    // MARK: - Parsing

    static func parse(from ev: NostrEvent) -> SpellEvent? {
        guard ev.known_kind == .spell else { return nil }

        var spell = SpellEvent(event: ev)
        var hasCmd = false
        var hasFilterTag = false

        for tag in ev.tags {
            guard tag.count >= 1 else { continue }
            let key = tag[0].string()

            switch key {
            case "cmd":
                guard tag.count >= 2 else { continue }
                let value = tag[1].string()
                guard let cmd = SpellCommand(rawValue: value) else { continue }
                spell.command = cmd
                hasCmd = true

            case "k":
                guard tag.count >= 2 else { continue }
                if let kind = UInt32(tag[1].string()) {
                    spell.kinds.append(kind)
                    hasFilterTag = true
                }

            case "authors":
                guard tag.count >= 2 else { continue }
                for i in 1..<Int(tag.count) {
                    spell.authors.append(SpellValue.parse(tag[i].string()))
                }
                hasFilterTag = true

            case "ids":
                guard tag.count >= 2 else { continue }
                for i in 1..<Int(tag.count) {
                    spell.ids.append(tag[i].string())
                }
                hasFilterTag = true

            case "tag":
                guard tag.count >= 3 else { continue }
                let letter = tag[1].string()
                var values: [SpellValue] = []
                for i in 2..<Int(tag.count) {
                    values.append(SpellValue.parse(tag[i].string()))
                }
                spell.tagFilters.append(SpellTagFilter(letter: letter, values: values))
                hasFilterTag = true

            case "limit":
                guard tag.count >= 2 else { continue }
                spell.limit = UInt32(tag[1].string())

            case "since":
                guard tag.count >= 2 else { continue }
                spell.since = SpellTimestamp.parse(tag[1].string())
                hasFilterTag = true

            case "until":
                guard tag.count >= 2 else { continue }
                spell.until = SpellTimestamp.parse(tag[1].string())
                hasFilterTag = true

            case "search":
                guard tag.count >= 2 else { continue }
                spell.search = tag[1].string()
                hasFilterTag = true

            case "relays":
                guard tag.count >= 2 else { continue }
                for i in 1..<Int(tag.count) {
                    spell.relays.append(tag[i].string())
                }

            case "name":
                guard tag.count >= 2 else { continue }
                spell.name = tag[1].string()

            case "alt":
                guard tag.count >= 2 else { continue }
                // Take the first alt tag (some events have duplicates)
                if spell.alt == nil {
                    spell.alt = tag[1].string()
                }

            case "t":
                guard tag.count >= 2 else { continue }
                spell.topics.append(tag[1].string())

            case "close-on-eose":
                spell.closeOnEose = true

            case "e":
                guard tag.count >= 2 else { continue }
                if spell.forkOf == nil {
                    spell.forkOf = NoteId(hex: tag[1].string())
                }

            default:
                break
            }
        }

        guard hasCmd, hasFilterTag else { return nil }

        return spell
    }

    // MARK: - Display

    /// Human-readable description from the content field, falling back to the name tag.
    var displayDescription: String {
        let text = event.content
        if !text.isEmpty {
            return text
        }
        return name ?? alt ?? ""
    }

    /// The display name for this spell.
    var displayName: String {
        return name ?? "Custom Feed"
    }

    /// Whether this spell uses any runtime variables that need resolution.
    var hasVariables: Bool {
        if authors.contains(where: { $0.isVariable }) {
            return true
        }
        for filter in tagFilters {
            if filter.values.contains(where: { $0.isVariable }) {
                return true
            }
        }
        return false
    }

    /// Whether this spell uses $contacts, which requires a non-empty contact list.
    var requiresContacts: Bool {
        let hasContactsAuthor = authors.contains { value in
            if case .variable(.contacts) = value { return true }
            return false
        }
        if hasContactsAuthor { return true }

        for filter in tagFilters {
            if filter.values.contains(where: { value in
                if case .variable(.contacts) = value { return true }
                return false
            }) {
                return true
            }
        }
        return false
    }
}
