//
//  NostrFilter.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation

struct NostrFilter: Codable, Equatable {
    var ids: [NoteId]?
    var kinds: [NostrKind]?
    var referenced_ids: [NoteId]?
    var pubkeys: [Pubkey]?
    var since: UInt32?
    var until: UInt32?
    var limit: UInt32?
    var authors: [Pubkey]?
    var hashtag: [String]?
    var parameter: [String]?
    var quotes: [NoteId]?

    private enum CodingKeys : String, CodingKey {
        case ids
        case kinds
        case referenced_ids = "#e"
        case pubkeys = "#p"
        case hashtag = "#t"
        case parameter = "#d"
        case quotes = "#q"
        case since
        case until
        case authors
        case limit
    }
    
    init(ids: [NoteId]? = nil, kinds: [NostrKind]? = nil, referenced_ids: [NoteId]? = nil, pubkeys: [Pubkey]? = nil, since: UInt32? = nil, until: UInt32? = nil, limit: UInt32? = nil, authors: [Pubkey]? = nil, hashtag: [String]? = nil, quotes: [NoteId]? = nil) {
        self.ids = ids
        self.kinds = kinds
        self.referenced_ids = referenced_ids
        self.pubkeys = pubkeys
        self.since = since
        self.until = until
        self.limit = limit
        self.authors = authors
        self.hashtag = hashtag
        self.quotes = quotes
    }
    
    public static func copy(from: NostrFilter) -> NostrFilter {
        NostrFilter(ids: from.ids, kinds: from.kinds, referenced_ids: from.referenced_ids, pubkeys: from.pubkeys, since: from.since, until: from.until, authors: from.authors, hashtag: from.hashtag)
    }
    
    public static func filter_hashtag(_ htags: [String]) -> NostrFilter {
        NostrFilter(hashtag: htags.map { $0.lowercased() })
    }
    
    /// Splits the filter on a given filter path/axis into chunked filters
    ///
    /// - Parameter path: The path where chunking should be done
    /// - Parameter chunk_size: The maximum size of each chunk.
    /// - Returns: An array of arrays, where each contained array is a chunk of the original array with up to `size` elements.
    func chunked(on path: ChunkPath, into chunk_size: Int) -> [Self] {
        let chunked_slices = self.get_slice(from: path).chunked(into: chunk_size)
        var chunked_filters: [NostrFilter] = []
        for chunked_slice in chunked_slices {
            var chunked_filter = self
            chunked_filter.apply_slice(chunked_slice)
            chunked_filters.append(chunked_filter)
        }
        return chunked_filters
    }
    
    /// Gets a slice from a NostrFilter on a given path/axis
    ///
    /// - Parameter path: The path where chunking should be done
    /// - Parameter chunk_size: The maximum size of each chunk.
    /// - Returns: An array of arrays, where each contained array is a chunk of the original array with up to `size` elements.
    func get_slice(from path: ChunkPath) -> Slice {
        switch path {
            case .pubkeys:
                return .pubkeys(self.pubkeys)
            case .authors:
                return .authors(self.authors)
        }
    }
    
    /// Overrides one member/axis of a NostrFilter using a specific slice
    /// - Parameter slice: The slice to be applied on this NostrFilter
    mutating func apply_slice(_ slice: Slice) {
        switch slice {
            case .pubkeys(let pubkeys):
                self.pubkeys = pubkeys
            case .authors(let authors):
                self.authors = authors
        }
    }
    
    
    /// A path to one of the axes of a NostrFilter.
    enum ChunkPath {
        case pubkeys
        case authors
        // Other paths/axes not supported yet
    }
    
    /// Represents the value of a single axis of a NostrFilter
    enum Slice {
        case pubkeys([Pubkey]?)
        case authors([Pubkey]?)
        
        func chunked(into chunk_size: Int) -> [Slice] {
            switch self {
                case .pubkeys(let array):
                    return (array ?? []).chunked(into: chunk_size).map({ .pubkeys($0) })
                case .authors(let array):
                    return (array ?? []).chunked(into: chunk_size).map({ .authors($0) })
            }
        }
    }
}

// MARK: - Conversion to/from ndb_filter

extension NostrFilter {
    // TODO: This function is long and repetitive, refactor it into something cleaner.
    func toNdbFilter() throws(NdbFilterConversionError) -> UnsafeMutablePointer<ndb_filter> {
        let filterPointer = UnsafeMutablePointer<ndb_filter>.allocate(capacity: 1)

        guard ndb_filter_init(filterPointer) == 1 else {
            filterPointer.deallocate()
            throw NdbFilterConversionError.failedToInitialize
        }
        
        // Handle `ids` field
        if let ids = self.ids {
            guard ndb_filter_start_field(filterPointer, NDB_FILTER_IDS) == 1 else {
                ndb_filter_destroy(filterPointer)
                filterPointer.deallocate()
                throw NdbFilterConversionError.failedToStartField
            }
            
            for noteId in ids {
                guard let idPointer = noteId.unsafePointer else {
                    ndb_filter_destroy(filterPointer)
                    filterPointer.deallocate()
                    throw NdbFilterConversionError.failedToAddElement
                }
                if ndb_filter_add_id_element(filterPointer, idPointer) != 1 {
                    ndb_filter_destroy(filterPointer)
                    filterPointer.deallocate()
                    throw NdbFilterConversionError.failedToAddElement
                }
            }
            
            ndb_filter_end_field(filterPointer)
        }
        
        // Handle `kinds` field
        if let kinds = self.kinds {
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
        if let referencedIds = self.referenced_ids {
            guard ndb_filter_start_tag_field(filterPointer, CChar(UnicodeScalar("e").value)) == 1 else {
                ndb_filter_destroy(filterPointer)
                filterPointer.deallocate()
                throw NdbFilterConversionError.failedToStartField
            }
            
            for refId in referencedIds {
                guard let refPointer = refId.unsafePointer else {
                    ndb_filter_destroy(filterPointer)
                    filterPointer.deallocate()
                    throw NdbFilterConversionError.failedToAddElement
                }
                if ndb_filter_add_id_element(filterPointer, refPointer) != 1 {
                    ndb_filter_destroy(filterPointer)
                    filterPointer.deallocate()
                    throw NdbFilterConversionError.failedToAddElement
                }
            }
            
            ndb_filter_end_field(filterPointer)
        }

        // Handle `pubkeys`
        if let pubkeys = self.pubkeys {
            guard ndb_filter_start_tag_field(filterPointer, CChar(UnicodeScalar("p").value)) == 1 else {
                ndb_filter_destroy(filterPointer)
                filterPointer.deallocate()
                throw NdbFilterConversionError.failedToStartField
            }

            for pubkey in pubkeys {
                guard let pubkeyPointer = pubkey.unsafePointer else {
                    ndb_filter_destroy(filterPointer)
                    filterPointer.deallocate()
                    throw NdbFilterConversionError.failedToAddElement
                }
                if ndb_filter_add_id_element(filterPointer, pubkeyPointer) != 1 {
                    ndb_filter_destroy(filterPointer)
                    filterPointer.deallocate()
                    throw NdbFilterConversionError.failedToAddElement
                }
            }
            
            ndb_filter_end_field(filterPointer)
        }
        
        // Handle `since`
        if let since = self.since {
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
        if let until = self.until {
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
        if let limit = self.limit {
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
        if let authors = self.authors {
            guard ndb_filter_start_field(filterPointer, NDB_FILTER_AUTHORS) == 1 else {
                ndb_filter_destroy(filterPointer)
                filterPointer.deallocate()
                throw NdbFilterConversionError.failedToStartField
            }

            for author in authors {
                guard let authorPointer = author.unsafePointer else {
                    ndb_filter_destroy(filterPointer)
                    filterPointer.deallocate()
                    throw NdbFilterConversionError.failedToAddElement
                }
                if ndb_filter_add_id_element(filterPointer, authorPointer) != 1 {
                    ndb_filter_destroy(filterPointer)
                    filterPointer.deallocate()
                    throw NdbFilterConversionError.failedToAddElement
                }
            }
            
            ndb_filter_end_field(filterPointer)
        }
        
        // Handle `hashtag`
        if let hashtags = self.hashtag {
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
        if let parameters = self.parameter {
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
        if let quotes = self.quotes {
            guard ndb_filter_start_tag_field(filterPointer, CChar(UnicodeScalar("q").value)) == 1 else {
                ndb_filter_destroy(filterPointer)
                filterPointer.deallocate()
                throw NdbFilterConversionError.failedToStartField
            }
            
            for quote in quotes {
                guard let quotePointer = quote.unsafePointer else {
                    ndb_filter_destroy(filterPointer)
                    filterPointer.deallocate()
                    throw NdbFilterConversionError.failedToAddElement
                }
                if ndb_filter_add_id_element(filterPointer, quotePointer) != 1 {
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
}
