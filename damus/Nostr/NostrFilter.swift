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

    private enum CodingKeys : String, CodingKey {
        case ids
        case kinds
        case referenced_ids = "#e"
        case pubkeys = "#p"
        case hashtag = "#t"
        case parameter = "#d"
        case since
        case until
        case authors
        case limit
    }
    
    init(ids: [NoteId]? = nil, kinds: [NostrKind]? = nil, referenced_ids: [NoteId]? = nil, pubkeys: [Pubkey]? = nil, since: UInt32? = nil, until: UInt32? = nil, limit: UInt32? = nil, authors: [Pubkey]? = nil, hashtag: [String]? = nil) {
        self.ids = ids
        self.kinds = kinds
        self.referenced_ids = referenced_ids
        self.pubkeys = pubkeys
        self.since = since
        self.until = until
        self.limit = limit
        self.authors = authors
        self.hashtag = hashtag
    }
    
    public static func copy(from: NostrFilter) -> NostrFilter {
        NostrFilter(ids: from.ids, kinds: from.kinds, referenced_ids: from.referenced_ids, pubkeys: from.pubkeys, since: from.since, until: from.until, authors: from.authors, hashtag: from.hashtag)
    }
    
    public static func filter_hashtag(_ htags: [String]) -> NostrFilter {
        NostrFilter(hashtag: htags.map { $0.lowercased() })
    }
}
