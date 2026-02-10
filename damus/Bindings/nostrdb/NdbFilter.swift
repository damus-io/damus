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
    
    /// Creates a new NdbFilter from a NostrFilter.
    /// - Parameter nostrFilter: The NostrFilter to convert
    /// - Throws: `NdbFilterError.conversionFailed` if the underlying conversion fails
    init(from nostrFilter: NostrFilter) throws {
        do {
            self.filterPointer = try Self.from(nostrFilter: nostrFilter)
        } catch {
            throw NdbFilterError.conversionFailed(error)
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
    private static func from(nostrFilter: NostrFilter) throws(NdbFilterConversionError) -> UnsafeMutablePointer<ndb_filter> {
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
