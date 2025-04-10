//
//  Ndb+.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-04-04.
//

/// ## Implementation notes
///
/// 1. This was created as a separate file because it contains dependencies to damus-specific structures such as `NostrFilter`, which is not yet available inside the NostrDB codebase.

import Foundation

extension Ndb {
    /// Subscribe to events matching the provided NostrFilters
    /// - Parameters:
    ///   - filters: Array of NostrFilter objects
    ///   - maxSimultaneousResults: Maximum number of initial results to return
    /// - Returns: AsyncStream of StreamItem events
    /// - Throws: NdbStreamError if subscription fails
    func subscribe(filters: [NostrFilter], maxSimultaneousResults: Int = 1000) throws(NdbStreamError) -> AsyncStream<StreamItem> {
        let ndbFilters: [NdbFilter]
        do {
            ndbFilters = try filters.toNdbFilters()
        } catch {
            throw .cannotConvertFilter(error)
        }
        return try self.subscribe(filters: ndbFilters, maxSimultaneousResults: maxSimultaneousResults)
    }
}
