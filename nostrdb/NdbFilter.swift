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
