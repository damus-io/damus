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
    var search: String?

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
        case search
    }
    
    init(
        ids: [NoteId]? = nil,
        kinds: [NostrKind]? = nil,
        referenced_ids: [NoteId]? = nil,
        pubkeys: [Pubkey]? = nil,
        since: UInt32? = nil,
        until: UInt32? = nil,
        limit: UInt32? = nil,
        authors: [Pubkey]? = nil,
        hashtag: [String]? = nil,
        quotes: [NoteId]? = nil,
        search: String? = nil
    ) {
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
        self.search = search
    }
    
    public static func copy(from: NostrFilter) -> NostrFilter {
        NostrFilter(
            ids: from.ids,
            kinds: from.kinds,
            referenced_ids: from.referenced_ids,
            pubkeys: from.pubkeys,
            since: from.since,
            until: from.until,
            limit: from.limit,
            authors: from.authors,
            hashtag: from.hashtag,
            quotes: from.quotes,
            search: from.search
        )
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
