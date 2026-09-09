//
//  AdvancedSearchQueryDSL.swift
//  damus
//
//  Created by William Casarin on 2026-09-02.
//

import Foundation

/// The one-line search language, in both directions: search-field text to an
/// ``AdvancedSearchQuery``, and a query back to text.
///
/// Both directions exist so the search field and the filter sheet can be the same
/// state. The sheet edits an ``AdvancedSearchQuery``; the field shows
/// ``render(_:calendar:authorToken:)`` of it; typing in the field runs
/// ``parse(_:now:calendar:resolveAuthor:)`` back. There is no second copy of the
/// query to drift.
///
/// ## Grammar
///
/// | Token | Means |
/// | --- | --- |
/// | `from:<npub\|nprofile\|hex\|@name\|nip05>` | author |
/// | `since:<YYYY-MM-DD\|7d\|24h\|2w\|3mo\|1y>` | oldest `created_at`, inclusive |
/// | `until:<same>` | newest `created_at`, inclusive |
/// | `"quoted run of text"` | exact phrase |
/// | `#hashtag` | a `t` tag the note must carry |
/// | `kind:note`, `kind:longform` | content type |
/// | `sort:newest`, `sort:oldest` | result order |
/// | anything else | a keyword |
///
/// ## Never fail a search
///
/// A token that looks like a filter but is not one degrades to a keyword rather
/// than erroring: `since:someday` searches for the word "since:someday", and a
/// bare `from:` searches for "from:". That is deliberate — a search field that
/// refuses to search is worse than one that searches for something slightly odd,
/// and it means the DSL can be introduced under an existing field without
/// breaking any query anyone already types.
///
/// The one exception is a `from:` value that is well-formed but names nobody in
/// the local profile index. Degrading that to a keyword would search note *text*
/// for "from:jb55", which is nonsense, and dropping it silently would widen the
/// search to every author. So it is reported in
/// ``ParseResult/unresolvedAuthors`` and contributes nothing, leaving the caller
/// to say who it could not find.
enum AdvancedSearchQueryDSL {
    // MARK: - Parsing

    /// What ``parse(_:now:calendar:resolveAuthor:)`` worked out.
    struct ParseResult: Equatable {
        /// The query to run.
        var query: AdvancedSearchQuery

        /// `from:` values that were well-formed but matched no local profile, in
        /// the order they were typed.
        ///
        /// These are *not* in ``query`` — see the type's discussion for why they
        /// are neither dropped silently nor degraded to keywords.
        var unresolvedAuthors: [String] = []

        /// True when at least one token was understood as something other than a
        /// plain keyword.
        ///
        /// This is the signal for "offer advanced search", not the shape of
        /// ``query``: an unresolved `from:` leaves no trace in the query but is
        /// very much an advanced query, and a phrase that happens to be one word
        /// is not the same request as that word as a keyword.
        var usedAdvancedSyntax: Bool = false
    }

    /// The calendar dates are interpreted in: Gregorian, in the device's current
    /// time zone.
    ///
    /// Fixed to Gregorian on purpose. `YYYY-MM-DD` is the format being typed, so
    /// resolving it through a non-Gregorian `Calendar.current` — which a user in
    /// Japan or Thailand may well have — would land on a completely different day.
    /// The time zone does follow the device, because a user typing a date means
    /// their own day, not a UTC one.
    static var defaultCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    /// Parses search-field text into a query.
    ///
    /// - Parameters:
    ///   - text: The raw contents of the search field.
    ///   - now: What relative dates like `7d` are relative to.
    ///   - calendar: The calendar absolute dates are resolved in. See
    ///     ``defaultCalendar``.
    ///   - resolveAuthor: Resolves a `from:` value that is a name, `@name` or
    ///     nip05 address rather than a key. Return `nil` for no match. Keys are
    ///     decoded before this is consulted, so it only ever sees names.
    static func parse(_ text: String,
                      now: Date = Date(),
                      calendar: Calendar? = nil,
                      resolveAuthor: (String) -> Pubkey? = { _ in nil }) -> ParseResult {
        let calendar = calendar ?? defaultCalendar

        var keywords: [String] = []
        var phrases: [String] = []
        var hashtags: [String] = []
        var authors: [Pubkey] = []
        var kinds: Set<NostrKind> = []
        var since: Date?
        var until: Date?
        var order: NdbSearchOrder = .newest_first
        var result = ParseResult(query: AdvancedSearchQuery())

        for token in tokenize(text) {
            // A token that opens with a quote is a phrase whatever it looks like,
            // so `"from:x"` is the escape hatch for searching for literal text
            // that happens to be shaped like a filter.
            if token.leadingQuote {
                phrases.append(token.text)
                result.usedAdvancedSyntax = true
                continue
            }

            if let (prefix, value) = split(prefixed: token.text), !value.isEmpty {
                switch prefix {
                case .from:
                    switch author(from: value, resolveAuthor: resolveAuthor) {
                    case .resolved(let pubkey):
                        authors.append(pubkey)
                        result.usedAdvancedSyntax = true
                        continue
                    case .unresolved:
                        result.unresolvedAuthors.append(value)
                        result.usedAdvancedSyntax = true
                        continue
                    case .notAnAuthor:
                        break   // degrade to a keyword
                    }

                case .since:
                    if let parsed = Self.date(from: value, bound: .since, now: now, calendar: calendar) {
                        since = parsed
                        result.usedAdvancedSyntax = true
                        continue
                    }

                case .until:
                    if let parsed = Self.date(from: value, bound: .until, now: now, calendar: calendar) {
                        until = parsed
                        result.usedAdvancedSyntax = true
                        continue
                    }

                case .kind:
                    if let parsed = Self.kind(from: value) {
                        kinds.insert(parsed)
                        result.usedAdvancedSyntax = true
                        continue
                    }

                case .sort:
                    if let parsed = Self.order(from: value) {
                        order = parsed
                        result.usedAdvancedSyntax = true
                        continue
                    }
                }
            }

            // Quoted, but after something that was not a prefix we recognise —
            // `foo"bar baz"`. Treat the whole thing as a phrase; the quotes were
            // clearly meant to make one.
            if token.quoted {
                phrases.append(token.text)
                result.usedAdvancedSyntax = true
                continue
            }

            if token.text.hasPrefix("#"), token.text.count > 1 {
                hashtags.append(token.text)
                result.usedAdvancedSyntax = true
                continue
            }

            keywords.append(token.text)
        }

        result.query = AdvancedSearchQuery(keywords: keywords,
                                           phrases: phrases,
                                           hashtags: hashtags,
                                           authors: authors,
                                           since: since,
                                           until: until,
                                           // an empty set restores the default
                                           kinds: kinds,
                                           order: order)
        return result
    }

    // MARK: - Rendering

    /// Renders `query` back into search-field text.
    ///
    /// Tokens come out in a fixed order — authors, dates, kind, sort, hashtags,
    /// phrases, keywords — so that equal queries render identically and editing
    /// the sheet does not reshuffle the field.
    ///
    /// Only what differs from the default is written: the default kind set and
    /// newest-first order render as nothing, which keeps a plain keyword search
    /// looking like one.
    ///
    /// - Parameters:
    ///   - query: The query to render.
    ///   - calendar: The calendar dates are rendered in. See ``defaultCalendar``.
    ///   - authorToken: How to name an author. Defaults to their npub, which
    ///     always round-trips; pass a display-name lookup for a friendlier field,
    ///     accepting that a name resolving to somebody else later will change what
    ///     the query means.
    static func render(_ query: AdvancedSearchQuery,
                       calendar: Calendar? = nil,
                       authorToken: (Pubkey) -> String = { $0.npub }) -> String {
        let calendar = calendar ?? defaultCalendar
        var tokens: [String] = []

        for author in query.authors {
            tokens.append(Prefix.from.token + quotedIfNeeded(authorToken(author)))
        }
        if let since = query.since {
            tokens.append(Prefix.since.token + render(date: since, bound: .since, calendar: calendar))
        }
        if let until = query.until {
            tokens.append(Prefix.until.token + render(date: until, bound: .until, calendar: calendar))
        }
        if query.kinds != AdvancedSearchQuery.defaultKinds {
            for kind in query.sortedKinds {
                guard let name = name(of: kind) else { continue }
                tokens.append(Prefix.kind.token + name)
            }
        }
        if query.order == .oldest_first {
            tokens.append(Prefix.sort.token + "oldest")
        }
        tokens += query.hashtags.map({ "#" + $0 })
        tokens += query.phrases.map({ "\"" + $0.replacingOccurrences(of: "\"", with: "") + "\"" })
        tokens += query.keywords

        return tokens.joined(separator: " ")
    }

    /// An author token that reads like a name but still means the right person.
    ///
    /// ``render(_:calendar:authorToken:)`` defaults to the npub, which always
    /// round-trips but fills a search field with unreadable keys. This uses
    /// `name` instead, but only when `resolve` maps it straight back to `pubkey` —
    /// so a display name shared with somebody else, or one the profile index ranks
    /// below another match, falls back to the key rather than quietly changing who
    /// the query is about.
    static func friendlyAuthorToken(for pubkey: Pubkey,
                                    name: String,
                                    resolve: (String) -> Pubkey?) -> String {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        // A name that is itself DSL — a leading `#`, an embedded quote, something
        // shaped like a prefix — would not survive the round trip whatever it
        // resolves to.
        guard !name.isEmpty, !name.hasPrefix("#"), !name.contains("\"") else { return pubkey.npub }
        if case .some = split(prefixed: name) { return pubkey.npub }
        guard resolve(name) == pubkey else { return pubkey.npub }
        return name
    }

    // MARK: - Tokens

    /// A prefix the DSL understands.
    enum Prefix: String, CaseIterable {
        case from, since, until, kind, sort

        /// The prefix as it is typed, including the colon.
        var token: String { rawValue + ":" }
    }

    /// One whitespace-separated run of the input.
    struct Token: Equatable {
        /// The text with any quote marks removed.
        let text: String
        /// Whether any part of it was inside double quotes.
        let quoted: Bool
        /// Whether the token *opened* with a quote.
        ///
        /// This is what separates `"from:x"` — a phrase, and the escape hatch for
        /// searching for text that looks like a filter — from `from:"John Doe"`,
        /// an author whose name has a space in it.
        let leadingQuote: Bool
    }

    /// Splits `text` on whitespace, keeping double-quoted runs together.
    ///
    /// An unterminated quote runs to the end of the input rather than being
    /// discarded, so a phrase is searchable while it is still being typed.
    static func tokenize(_ text: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        var quoted = false
        var leadingQuote = false
        var inQuotes = false

        func flush() {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                tokens.append(Token(text: trimmed, quoted: quoted, leadingQuote: leadingQuote))
            }
            current = ""
            quoted = false
            leadingQuote = false
        }

        for character in text {
            if character == "\"" {
                if current.isEmpty && !quoted { leadingQuote = true }
                inQuotes.toggle()
                quoted = true
            } else if character.isWhitespace && !inQuotes {
                flush()
            } else {
                current.append(character)
            }
        }
        flush()

        return tokens
    }

    /// Splits a token into its prefix and value, or `nil` when it carries none.
    ///
    /// Prefixes are matched case-insensitively, so `From:jb55` works.
    static func split(prefixed token: String) -> (Prefix, String)? {
        guard let colon = token.firstIndex(of: ":") else { return nil }
        guard let prefix = Prefix(rawValue: String(token[token.startIndex..<colon]).lowercased()) else {
            return nil
        }
        return (prefix, String(token[token.index(after: colon)...]))
    }

    /// Wraps a value in quotes if it contains whitespace, so `from:John Doe`
    /// survives a round trip.
    private static func quotedIfNeeded(_ value: String) -> String {
        guard value.contains(where: { $0.isWhitespace }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "") + "\""
    }

    // MARK: - Authors

    private enum AuthorToken {
        case resolved(Pubkey)
        /// Looked like somebody's name, but nobody local matched.
        case unresolved
        /// Did not look like an author reference at all.
        case notAnAuthor
    }

    private static func author(from value: String, resolveAuthor: (String) -> Pubkey?) -> AuthorToken {
        let value = remove_nostr_uri_prefix(value)

        if let pubkey = hex_decode_pubkey(value) { return .resolved(pubkey) }

        if value.hasPrefix("npub") {
            guard let pubkey = bech32_pubkey_decode(value) else { return .notAnAuthor }
            return .resolved(pubkey)
        }

        if value.hasPrefix("nprofile") {
            guard case .nprofile(let nprofile) = Bech32Object.parse(value) else { return .notAnAuthor }
            return .resolved(nprofile.author)
        }

        // A name, `@name`, or a nip05 address. Only the local profile index can
        // say who that is.
        let name = value.hasPrefix("@") ? String(value.dropFirst()) : value
        guard !name.isEmpty else { return .notAnAuthor }
        guard let pubkey = resolveAuthor(name) else { return .unresolved }
        return .resolved(pubkey)
    }

    // MARK: - Dates

    /// Which bound is being parsed, which is what decides what a bare date means.
    enum DateBound {
        case since
        case until
    }

    /// Parses a `since:`/`until:` value.
    ///
    /// A bare `YYYY-MM-DD` covers the whole of that day: `since:2026-01-05` starts
    /// at 00:00:00 and `until:2026-01-05` ends at 23:59:59. Both bounds being
    /// inclusive is what makes that work — `since:X until:X` is exactly the day X.
    /// Add a `THH:MM:SS` for a specific moment.
    ///
    /// Everything is floored to whole seconds, because a nostr `created_at` is,
    /// and because it keeps ``render(_:calendar:authorToken:)`` lossless.
    static func date(from value: String, bound: DateBound, now: Date, calendar: Calendar) -> Date? {
        if let relative = relativeDate(from: value, now: now, calendar: calendar) {
            return floored(relative)
        }

        let parts = value.uppercased().split(separator: "T", maxSplits: 1, omittingEmptySubsequences: false)
        let day = parts[0].split(separator: "-", omittingEmptySubsequences: false)
        guard day.count == 3,
              let year = Int(day[0]), day[0].count == 4,
              let month = Int(day[1]), let dayOfMonth = Int(day[2]),
              (1...12).contains(month), (1...31).contains(dayOfMonth)
        else { return nil }

        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = dayOfMonth

        if parts.count == 2 {
            let time = parts[1].split(separator: ":", omittingEmptySubsequences: false)
            guard (2...3).contains(time.count),
                  let hour = Int(time[0]), let minute = Int(time[1]),
                  (0...23).contains(hour), (0...59).contains(minute)
            else { return nil }
            let second = time.count == 3 ? Int(time[2]) : 0
            guard let second, (0...59).contains(second) else { return nil }

            components.hour = hour
            components.minute = minute
            components.second = second
            guard let date = calendar.date(from: components), components.isValidDate else { return nil }
            return floored(date)
        }

        components.hour = 0
        components.minute = 0
        components.second = 0
        guard let startOfDay = calendar.date(from: components), components.isValidDate else { return nil }

        switch bound {
        case .since: return floored(startOfDay)
        case .until: return endOfDay(startOfDay, calendar: calendar)
        }
    }

    /// Parses `7d`, `24h`, `2w`, `3mo`, `1y` into a date that far in the past.
    private static func relativeDate(from value: String, now: Date, calendar: Calendar) -> Date? {
        let digits = value.prefix(while: { $0.isNumber })
        guard !digits.isEmpty, let amount = Int(digits) else { return nil }

        let component: Calendar.Component
        switch value.dropFirst(digits.count).lowercased() {
        case "h": component = .hour
        case "d": component = .day
        case "w": component = .weekOfYear
        case "mo": component = .month
        case "y": component = .year
        default: return nil
        }

        return calendar.date(byAdding: component, value: -amount, to: now)
    }

    /// The last whole second of the day `startOfDay` begins.
    ///
    /// Built by stepping a day forward and back a second rather than by setting
    /// 23:59:59, so it stays right on the days daylight saving makes 23 or 25
    /// hours long.
    private static func endOfDay(_ startOfDay: Date, calendar: Calendar) -> Date? {
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else { return nil }
        return floored(nextDay.addingTimeInterval(-1))
    }

    private static func floored(_ date: Date) -> Date {
        Date(timeIntervalSince1970: date.timeIntervalSince1970.rounded(.down))
    }

    /// Snaps `date` to the edge of its day that `bound` means.
    ///
    /// The same rule a bare `YYYY-MM-DD` follows: a `since` starts the day, an
    /// `until` ends it. Exposed because a date-only picker means exactly this — a
    /// picker that left the time of day alone would silently make an inclusive
    /// `until` cut the day off wherever the clock happened to be.
    static func dayBound(_ date: Date, bound: DateBound, calendar: Calendar? = nil) -> Date {
        let calendar = calendar ?? defaultCalendar
        let startOfDay = calendar.startOfDay(for: date)
        switch bound {
        case .since: return floored(startOfDay)
        case .until: return endOfDay(startOfDay, calendar: calendar) ?? floored(date)
        }
    }

    /// Renders a bound back to the shortest form that parses to the same second.
    ///
    /// A `since` sitting exactly at midnight, or an `until` sitting exactly on the
    /// last second of a day, is written as a bare `YYYY-MM-DD` — which is how it
    /// was almost certainly typed. Anything else gets the full `YYYY-MM-DDTHH:MM:SS`
    /// so the round trip stays exact.
    static func render(date: Date, bound: DateBound, calendar: Calendar) -> String {
        let date = floored(date)
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return ""
        }
        let ymd = String(format: "%04d-%02d-%02d", year, month, day)

        let startOfDay = calendar.startOfDay(for: date)
        switch bound {
        case .since where startOfDay == date:
            return ymd
        case .until where endOfDay(startOfDay, calendar: calendar) == date:
            return ymd
        default:
            return ymd + String(format: "T%02d:%02d:%02d",
                                components.hour ?? 0, components.minute ?? 0, components.second ?? 0)
        }
    }

    // MARK: - Kinds and order

    /// Maps a `kind:` value to a kind.
    ///
    /// Only fulltext-indexed kinds are addressable; numeric aliases name the
    /// same indexed content types.
    static func kind(from value: String) -> NostrKind? {
        switch value.lowercased() {
        case "note", "notes", "text", "post", "posts", "1":
            return .text
        case "voice", "audio", "1808":
            return .voice
        case "longform", "long-form", "long_form", "article", "articles", "30023":
            return .longform
        default:
            return nil
        }
    }

    /// The canonical `kind:` value for a kind, or `nil` when it has no name in the
    /// DSL — which is every kind the search cannot reach anyway.
    static func name(of kind: NostrKind) -> String? {
        switch kind {
        case .text: return "note"
        case .voice: return "voice"
        case .longform: return "longform"
        default: return nil
        }
    }

    static func order(from value: String) -> NdbSearchOrder? {
        switch value.lowercased() {
        case "oldest", "old", "asc", "ascending": return .oldest_first
        case "newest", "new", "desc", "descending": return .newest_first
        default: return nil
        }
    }
}
