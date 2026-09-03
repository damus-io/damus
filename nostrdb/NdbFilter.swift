//
//  NdbFilter.swift
//  damus
//
//  Created by Daniel D'Aquino on 2025-06-02.
//

import Foundation

/// A safe Swift wrapper around `UnsafeMutablePointer<ndb_filter>` that manages memory automatically.
///
/// This class provides a safe interface to the underlying C `ndb_filter` structure, handling
/// memory allocation and deallocation automatically. It eliminates the need for manual memory
/// management when working with NostrDB filters.
///
/// ## Usage
/// ```swift
/// let nostrFilter = NostrFilter(kinds: [.text_note])
/// let ndbFilter = try NdbFilter(from: nostrFilter)
/// // Use ndbFilter.ndbFilter or ndbFilter.unsafePointer as needed
/// // Memory is automatically cleaned up when ndbFilter goes out of scope
/// ```
class NdbFilter {
    private let filterPointer: UnsafeMutablePointer<ndb_filter>
    /// Owns the predicate handed to nostrdb, if this filter has one.
    ///
    /// nostrdb stores the `ctx` we give it as a bare pointer and never retains it,
    /// so the box has to live exactly as long as the filter does.
    private let customPredicate: CustomPredicate?

    /// Creates a new NdbFilter from a NostrFilter.
    /// - Parameter nostrFilter: The NostrFilter to convert
    /// - Throws: `NdbFilterError.conversionFailed` if the underlying conversion fails
    convenience init(from nostrFilter: NostrFilter) throws {
        try self.init(from: nostrFilter, matching: nil)
    }

    /// Creates a new NdbFilter from a NostrFilter, plus an arbitrary Swift predicate.
    ///
    /// The predicate becomes an `NDB_FILTER_CUSTOM` field, which nostrdb checks
    /// alongside the converted fields: every field has to match, so `matching`
    /// narrows the filter, it can never widen it. Because it is checked wherever
    /// `ndb_filter_matches` is — including inside the text-search index walk,
    /// before a candidate takes up a result slot — rejecting a note here is not the
    /// same as dropping it from the results afterwards.
    ///
    /// - Warning: The note handed to `matching` is borrowed for the duration of the
    ///   call. It is only valid while the query's transaction is open, and nostrdb
    ///   does not tell us its size, so the note is created with a size of zero: the
    ///   predicate must not let it escape, and must not call `to_owned()` on it
    ///   (that would copy zero bytes). Read what you need and return.
    ///
    /// - Parameters:
    ///   - nostrFilter: The NostrFilter to convert.
    ///   - matching: A predicate run against each candidate note, returning `true`
    ///     to keep it. Pass `nil` for no custom field.
    /// - Throws: `NdbFilterError.conversionFailed` if the underlying conversion fails
    init(from nostrFilter: NostrFilter, matching: (@Sendable (NostrEvent) -> Bool)?) throws {
        let predicate = matching.map({ CustomPredicate($0) })
        do {
            self.filterPointer = try Self.from(nostrFilter: nostrFilter, matching: predicate)
        } catch {
            throw NdbFilterError.conversionFailed(error)
        }
        self.customPredicate = predicate
    }

    /// A reference-typed box around a Swift predicate, so it can be handed to C as
    /// an opaque `ctx` pointer and recovered on the other side.
    fileprivate final class CustomPredicate {
        let matches: @Sendable (NostrEvent) -> Bool

        init(_ matches: @escaping @Sendable (NostrEvent) -> Bool) {
            self.matches = matches
        }
    }

    /// Provides access to the underlying `ndb_filter` structure.
    /// - Returns: The underlying `ndb_filter` value (not a pointer)
    var ndbFilter: ndb_filter {
        return filterPointer.pointee
    }
    
    /// Provides access to the underlying unsafe pointer when needed for C interop.
    /// - Warning: The caller must not deallocate this pointer. It will be automatically 
    ///           deallocated when this NdbFilter is destroyed.
    /// - Returns: The unsafe mutable pointer to the underlying ndb_filter
    var unsafePointer: UnsafeMutablePointer<ndb_filter> {
        return filterPointer
    }
    
    /// Creates multiple NdbFilter instances from an array of NostrFilters.
    /// - Parameter nostrFilters: Array of NostrFilter instances to convert
    /// - Returns: Array of NdbFilter instances
    /// - Throws: `NdbFilterError.conversionFailed` if any conversion fails
    static func create(from nostrFilters: [NostrFilter]) throws -> [NdbFilter] {
        return try nostrFilters.map { try NdbFilter(from: $0) }
    }
    
    // MARK: - Conversion to/from ndb_filter
    
    // TODO: This function is long and repetitive, refactor it into something cleaner.
    private static func from(nostrFilter: NostrFilter, matching predicate: CustomPredicate?) throws(NdbFilterConversionError) -> UnsafeMutablePointer<ndb_filter> {
        let filterPointer = UnsafeMutablePointer<ndb_filter>.allocate(capacity: 1)

        guard ndb_filter_init(filterPointer) == 1 else {
            filterPointer.deallocate()
            throw NdbFilterConversionError.failedToInitialize
        }
        
        // Handle `ids` field
        if let ids = nostrFilter.ids {
            guard ndb_filter_start_field(filterPointer, NDB_FILTER_IDS) == 1 else {
                ndb_filter_destroy(filterPointer)
                filterPointer.deallocate()
                throw NdbFilterConversionError.failedToStartField
            }
            
            for noteId in ids {
                do {
                    try noteId.withUnsafePointer({ idPointer in
                        if ndb_filter_add_id_element(filterPointer, idPointer) != 1 {
                            ndb_filter_destroy(filterPointer)
                            filterPointer.deallocate()
                            throw NdbFilterConversionError.failedToAddElement
                        }
                    })
                }
                catch {
                    ndb_filter_destroy(filterPointer)
                    filterPointer.deallocate()
                    throw NdbFilterConversionError.failedToAddElement
                }
            }
            
            ndb_filter_end_field(filterPointer)
        }
        
        // Handle `kinds` field
        if let kinds = nostrFilter.kinds {
            guard ndb_filter_start_field(filterPointer, NDB_FILTER_KINDS) == 1 else {
                ndb_filter_destroy(filterPointer)
                filterPointer.deallocate()
                throw NdbFilterConversionError.failedToStartField
            }
            
            for kind in kinds {
                if ndb_filter_add_int_element(filterPointer, UInt64(kind.rawValue)) != 1 {
                    ndb_filter_destroy(filterPointer)
                    filterPointer.deallocate()
                    throw NdbFilterConversionError.failedToAddElement
                }
            }
            
            ndb_filter_end_field(filterPointer)
        }
        
        // Handle `referenced_ids` field
        if let referencedIds = nostrFilter.referenced_ids {
            guard ndb_filter_start_tag_field(filterPointer, CChar(UnicodeScalar("e").value)) == 1 else {
                ndb_filter_destroy(filterPointer)
                filterPointer.deallocate()
                throw NdbFilterConversionError.failedToStartField
            }
            
            for refId in referencedIds {
                do {
                    try refId.withUnsafePointer({ refPointer in
                        if ndb_filter_add_id_element(filterPointer, refPointer) != 1 {
                            ndb_filter_destroy(filterPointer)
                            filterPointer.deallocate()
                            throw NdbFilterConversionError.failedToAddElement
                        }
                    })
                }
                catch {
                    ndb_filter_destroy(filterPointer)
                    filterPointer.deallocate()
                    throw NdbFilterConversionError.failedToAddElement
                }
            }
            
            ndb_filter_end_field(filterPointer)
        }

        // Handle `pubkeys`
        if let pubkeys = nostrFilter.pubkeys {
            guard ndb_filter_start_tag_field(filterPointer, CChar(UnicodeScalar("p").value)) == 1 else {
                ndb_filter_destroy(filterPointer)
                filterPointer.deallocate()
                throw NdbFilterConversionError.failedToStartField
            }

            for pubkey in pubkeys {
                do {
                    try pubkey.withUnsafePointer({ pubkeyPointer in
                        if ndb_filter_add_id_element(filterPointer, pubkeyPointer) != 1 {
                            ndb_filter_destroy(filterPointer)
                            filterPointer.deallocate()
                            throw NdbFilterConversionError.failedToAddElement
                        }
                    })
                }
                catch {
                    ndb_filter_destroy(filterPointer)
                    filterPointer.deallocate()
                    throw NdbFilterConversionError.failedToAddElement
                }
            }
            
            ndb_filter_end_field(filterPointer)
        }
        
        // Handle `since`
        if let since = nostrFilter.since {
            if ndb_filter_start_field(filterPointer, NDB_FILTER_SINCE) != 1 {
                ndb_filter_destroy(filterPointer)
                filterPointer.deallocate()
                throw NdbFilterConversionError.failedToAddElement
            }
            
            if ndb_filter_add_int_element(filterPointer, UInt64(since)) != 1 {
                ndb_filter_destroy(filterPointer)
                filterPointer.deallocate()
                throw NdbFilterConversionError.failedToAddElement
            }
            
            ndb_filter_end_field(filterPointer)
        }

        // Handle `until`
        if let until = nostrFilter.until {
            if ndb_filter_start_field(filterPointer, NDB_FILTER_UNTIL) != 1 {
                ndb_filter_destroy(filterPointer)
                filterPointer.deallocate()
                throw NdbFilterConversionError.failedToAddElement
            }
            
            if ndb_filter_add_int_element(filterPointer, UInt64(until)) != 1 {
                ndb_filter_destroy(filterPointer)
                filterPointer.deallocate()
                throw NdbFilterConversionError.failedToAddElement
            }
            
            ndb_filter_end_field(filterPointer)
        }

        // Handle `limit`
        if let limit = nostrFilter.limit {
            if ndb_filter_start_field(filterPointer, NDB_FILTER_LIMIT) != 1 {
                ndb_filter_destroy(filterPointer)
                filterPointer.deallocate()
                throw NdbFilterConversionError.failedToAddElement
            }
            
            if ndb_filter_add_int_element(filterPointer, UInt64(limit)) != 1 {
                ndb_filter_destroy(filterPointer)
                filterPointer.deallocate()
                throw NdbFilterConversionError.failedToAddElement
            }
            
            ndb_filter_end_field(filterPointer)
        }
        
        // Handle `authors`
        if let authors = nostrFilter.authors {
            guard ndb_filter_start_field(filterPointer, NDB_FILTER_AUTHORS) == 1 else {
                ndb_filter_destroy(filterPointer)
                filterPointer.deallocate()
                throw NdbFilterConversionError.failedToStartField
            }

            for author in authors {
                do {
                    try author.withUnsafePointer({ authorPointer in
                        if ndb_filter_add_id_element(filterPointer, authorPointer) != 1 {
                            ndb_filter_destroy(filterPointer)
                            filterPointer.deallocate()
                            throw NdbFilterConversionError.failedToAddElement
                        }
                    })
                }
                catch {
                    ndb_filter_destroy(filterPointer)
                    filterPointer.deallocate()
                    throw NdbFilterConversionError.failedToAddElement
                }
                
            }
            
            ndb_filter_end_field(filterPointer)
        }
        
        // Handle `hashtag`
        if let hashtags = nostrFilter.hashtag {
            guard ndb_filter_start_tag_field(filterPointer, CChar(UnicodeScalar("t").value)) == 1 else {
                ndb_filter_destroy(filterPointer)
                filterPointer.deallocate()
                throw NdbFilterConversionError.failedToStartField
            }

            for tag in hashtags {
                if ndb_filter_add_str_element(filterPointer, tag.cString(using: .utf8)) != 1 {
                    ndb_filter_destroy(filterPointer)
                    filterPointer.deallocate()
                    throw NdbFilterConversionError.failedToAddElement
                }
            }
            ndb_filter_end_field(filterPointer)
        }
        
        // Handle `parameter`
        if let parameters = nostrFilter.parameter {
            guard ndb_filter_start_tag_field(filterPointer, CChar(UnicodeScalar("d").value)) == 1 else {
                ndb_filter_destroy(filterPointer)
                filterPointer.deallocate()
                throw NdbFilterConversionError.failedToStartField
            }

            for parameter in parameters {
                if ndb_filter_add_str_element(filterPointer, parameter.cString(using: .utf8)) != 1 {
                    ndb_filter_destroy(filterPointer)
                    filterPointer.deallocate()
                    throw NdbFilterConversionError.failedToAddElement
                }
            }
            ndb_filter_end_field(filterPointer)
        }

        // Handle `quotes`
        if let quotes = nostrFilter.quotes {
            guard ndb_filter_start_tag_field(filterPointer, CChar(UnicodeScalar("q").value)) == 1 else {
                ndb_filter_destroy(filterPointer)
                filterPointer.deallocate()
                throw NdbFilterConversionError.failedToStartField
            }
            
            for quote in quotes {
                do {
                    try quote.withUnsafePointer({ quotePointer in
                        if ndb_filter_add_id_element(filterPointer, quotePointer) != 1 {
                            ndb_filter_destroy(filterPointer)
                            filterPointer.deallocate()
                            throw NdbFilterConversionError.failedToAddElement
                        }
                    })
                }
                catch {
                    ndb_filter_destroy(filterPointer)
                    filterPointer.deallocate()
                    throw NdbFilterConversionError.failedToAddElement
                }
                
            }
            
            ndb_filter_end_field(filterPointer)
        }

        // Handle `search`
        if let search = nostrFilter.search {
            guard ndb_filter_start_field(filterPointer, NDB_FILTER_SEARCH) == 1 else {
                ndb_filter_destroy(filterPointer)
                filterPointer.deallocate()
                throw NdbFilterConversionError.failedToStartField
            }

            if ndb_filter_add_str_element(filterPointer, search.cString(using: .utf8)) != 1 {
                ndb_filter_destroy(filterPointer)
                filterPointer.deallocate()
                throw NdbFilterConversionError.failedToAddElement
            }

            ndb_filter_end_field(filterPointer)
        }

        // Handle the custom Swift predicate
        if let predicate {
            guard ndb_filter_start_field(filterPointer, NDB_FILTER_CUSTOM) == 1 else {
                ndb_filter_destroy(filterPointer)
                filterPointer.deallocate()
                throw NdbFilterConversionError.failedToStartField
            }

            // Unretained: `predicate` is stored on the NdbFilter being built, so it
            // outlives every call nostrdb can make through this pointer.
            let ctx = Unmanaged.passUnretained(predicate).toOpaque()
            if ndb_filter_add_custom_filter_element(filterPointer, custom_filter_trampoline, ctx) != 1 {
                ndb_filter_destroy(filterPointer)
                filterPointer.deallocate()
                throw NdbFilterConversionError.failedToAddElement
            }

            ndb_filter_end_field(filterPointer)
        }

        // Finalize the filter
        guard ndb_filter_end(filterPointer) == 1 else {
            ndb_filter_destroy(filterPointer)
            filterPointer.deallocate()
            throw NdbFilterConversionError.failedToFinalize
        }

        return filterPointer
    }

    enum NdbFilterConversionError: Error {
        case failedToInitialize
        case failedToStartField
        case failedToAddElement
        case failedToFinalize
    }
    
    deinit {
        ndb_filter_destroy(filterPointer)
        filterPointer.deallocate()
    }
}

/// The C entry point for `NDB_FILTER_CUSTOM` fields built by `NdbFilter`.
///
/// Non-capturing by necessity — nostrdb takes a plain function pointer — so the
/// Swift predicate travels through the `ctx` pointer instead. Anything unexpected
/// (a null context or note) keeps the note: a broken filter should never be able
/// to silently hide notes.
private let custom_filter_trampoline: @convention(c) (UnsafeMutableRawPointer?, OpaquePointer?) -> Bool = { ctx, note_ptr in
    guard let ctx, let note_ptr else { return true }
    let predicate = Unmanaged<NdbFilter.CustomPredicate>.fromOpaque(ctx).takeUnretainedValue()
    // Size zero: nostrdb hands us no length here, and the note is only borrowed
    // for this call. See the warning on `init(from:matching:)`.
    let note = NostrEvent(note: ndb_note_ptr(ptr: note_ptr), size: 0, owned: false, key: nil)
    return predicate.matches(note)
}

// MARK: - Building a filter field by field

/// The fields an `ndb_filter` can carry, mirroring `enum ndb_filter_fieldtype`.
///
/// Generic tag fields — the `#e`, `#p`, `#t` … of a nostr filter — are all
/// ``tags`` on the C side, and are opened by their tag character rather than by
/// this enum. See ``NdbFilterBuilder/tagField(_:_:)``.
enum NdbFilterField {
    case ids
    case authors
    case kinds
    case tags
    case since
    case until
    case limit
    case search
    case relays
    case custom

    var cValue: ndb_filter_fieldtype {
        switch self {
        case .ids:     return NDB_FILTER_IDS
        case .authors: return NDB_FILTER_AUTHORS
        case .kinds:   return NDB_FILTER_KINDS
        case .tags:    return NDB_FILTER_TAGS
        case .since:   return NDB_FILTER_SINCE
        case .until:   return NDB_FILTER_UNTIL
        case .limit:   return NDB_FILTER_LIMIT
        case .search:  return NDB_FILTER_SEARCH
        case .relays:  return NDB_FILTER_RELAYS
        case .custom:  return NDB_FILTER_CUSTOM
        }
    }
}

/// Errors from building an `ndb_filter`.
enum NdbFilterBuildError: Error, LocalizedError {
    /// `ndb_filter_init` refused to initialize the filter.
    case initializationFailed
    /// `ndb_filter_start_field` refused to open the field.
    case fieldStartFailed(field: NdbFilterField)
    /// `ndb_filter_start_tag_field` refused to open the tag field.
    case tagFieldStartFailed(tag: Character)
    /// A tag has to be a single ASCII character to be a tag on the C side.
    case tagNotASCII(tag: Character)
    /// nostrdb rejected an element. Usually it is the wrong kind of element for
    /// the open field: a string in `authors`, a second value in `since`.
    case elementRejected
    /// An id element was not the 32 bytes nostrdb reads from the pointer.
    case invalidIdLength(bytes: Int)
    /// `ndb_filter_end` refused to finalize the filter.
    case finalizationFailed

    var errorDescription: String? {
        switch self {
        case .initializationFailed:
            return "nostrdb failed to initialize the filter."
        case .fieldStartFailed(let field):
            return "nostrdb refused to start the \(field) field."
        case .tagFieldStartFailed(let tag):
            return "nostrdb refused to start the #\(tag) tag field."
        case .tagNotASCII(let tag):
            return "A filter tag has to be a single ASCII character, not \(tag)."
        case .elementRejected:
            return "nostrdb rejected a filter element."
        case .invalidIdLength(let bytes):
            return "Expected a 32-byte id element, got \(bytes) bytes."
        case .finalizationFailed:
            return "nostrdb failed to finalize the filter."
        }
    }
}

/// An `ndb_filter` under construction.
///
/// nostrdb builds filters imperatively: `ndb_filter_init`, then per field a
/// `ndb_filter_start_field` / add elements / `ndb_filter_end_field` sequence, and
/// finally `ndb_filter_end`. Every one of those steps can fail, and each failure
/// leaves behind a filter somebody has to destroy — which is what makes the
/// open-coded version so repetitive, and so easy to get wrong in the direction
/// of a leak.
///
/// This wraps the sequence, so a caller describes the filter it wants and never
/// sees a half-built one:
///
/// ```swift
/// try NdbFilterBuilder.build(into: slot, { filter in
///     try filter.field(.since, { try $0.add(int: UInt64(since)) })
///     try filter.field(.authors, { field in
///         for author in authors { try field.add(id: author) }
///     })
/// })
/// ```
struct NdbFilterBuilder {
    /// The filter being built: `ndb_filter_init` has run on it, and
    /// `ndb_filter_end` has not.
    private let filter: UnsafeMutablePointer<ndb_filter>

    /// Initializes `slot` and builds a filter into it.
    ///
    /// On any failure — nostrdb refusing a step, or `body` throwing — the
    /// partially built filter is destroyed and `slot` is left uninitialized, free
    /// for the caller to reuse or discard. That is the same contract nostrdb's own
    /// builders follow, and it is what lets a caller treat a throw as "nothing
    /// happened".
    ///
    /// - Parameters:
    ///   - slot: Uninitialized memory for one `ndb_filter`. The caller owns the
    ///     allocation and, once this returns successfully, owes it an
    ///     `ndb_filter_destroy`.
    ///   - body: Adds the fields. Fields may be added in any order.
    static func build(into slot: UnsafeMutablePointer<ndb_filter>,
                      _ body: (NdbFilterBuilder) throws -> Void) throws {
        guard ndb_filter_init(slot) == 1 else {
            throw NdbFilterBuildError.initializationFailed
        }

        do {
            try body(NdbFilterBuilder(filter: slot))
            guard ndb_filter_end(slot) == 1 else {
                throw NdbFilterBuildError.finalizationFailed
            }
        } catch {
            ndb_filter_destroy(slot)
            throw error
        }
    }

    /// Opens `field`, runs `body` to add its elements, and closes it.
    ///
    /// If `body` throws, the field is left open on purpose: ``build(into:_:)``
    /// destroys the whole filter on the way out, which releases it either way, and
    /// closing a field mid-failure would only make the wreckage look valid.
    func field(_ field: NdbFilterField, _ body: (NdbFilterBuilder) throws -> Void) throws {
        guard ndb_filter_start_field(filter, field.cValue) == 1 else {
            throw NdbFilterBuildError.fieldStartFailed(field: field)
        }
        try body(self)
        ndb_filter_end_field(filter)
    }

    /// Opens the generic tag field for `tag` — the `#e`, `#p`, `#t` … of a nostr
    /// filter — runs `body` to add its elements, and closes it.
    func tagField(_ tag: Character, _ body: (NdbFilterBuilder) throws -> Void) throws {
        guard let ascii = tag.asciiValue else {
            throw NdbFilterBuildError.tagNotASCII(tag: tag)
        }
        guard ndb_filter_start_tag_field(filter, CChar(ascii)) == 1 else {
            throw NdbFilterBuildError.tagFieldStartFailed(tag: tag)
        }
        try body(self)
        ndb_filter_end_field(filter)
    }

    /// Adds an integer element to the open field.
    func add(int value: UInt64) throws {
        guard ndb_filter_add_int_element(filter, value) == 1 else {
            throw NdbFilterBuildError.elementRejected
        }
    }

    /// Adds a 32-byte id element — a note id, a pubkey, anything nostr spells as
    /// 32 bytes — to the open field.
    func add(id: some IdType) throws {
        let bytes = id.id
        // nostrdb reads 32 bytes from the pointer with no length to check against,
        // so a short id would have it read past the end of our buffer.
        guard bytes.count == 32 else {
            throw NdbFilterBuildError.invalidIdLength(bytes: bytes.count)
        }
        try bytes.withUnsafeBytes({ raw in
            guard let base = raw.bindMemory(to: UInt8.self).baseAddress,
                  ndb_filter_add_id_element(filter, base) == 1 else {
                throw NdbFilterBuildError.elementRejected
            }
        })
    }

    /// Adds a string element to the open field.
    ///
    /// nostrdb copies the bytes into the filter's own buffer, so `value` does not
    /// have to outlive this call.
    func add(string value: String) throws {
        guard ndb_filter_add_str_element(filter, value) == 1 else {
            throw NdbFilterBuildError.elementRejected
        }
    }
}

/// Errors that can occur when working with NdbFilter.
enum NdbFilterError: Error {
    /// Thrown when conversion from NostrFilter to NdbFilter fails.
    /// - Parameter Error: The underlying error that caused the conversion to fail
    case conversionFailed(Error)
}

/// Extension to create multiple NdbFilters safely from an array of NostrFilters.
extension Array where Element == NostrFilter {
    /// Converts an array of NostrFilters to NdbFilters.
    /// - Returns: Array of NdbFilter instances
    /// - Throws: `NdbFilterError.conversionFailed` if any conversion fails
    func toNdbFilters() throws -> [NdbFilter] {
        return try self.map { try NdbFilter(from: $0) }
    }
}
