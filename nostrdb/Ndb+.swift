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
    func subscribe(filters: [NostrFilter], maxSimultaneousResults: Int = 1000) throws -> AsyncStream<StreamItem> {
        let ndbFilters: [NdbFilter]
        do {
            ndbFilters = try filters.toNdbFilters()
        } catch {
            throw NdbStreamError.cannotConvertFilter(error)
        }
        return try self.subscribe(filters: ndbFilters, maxSimultaneousResults: maxSimultaneousResults)
    }
    
    /// Determines if a given note was seen on any of the listed relay URLs
    func was(noteKey: NoteKey, seenOnAnyOf relayUrls: [RelayURL], txn: SafeNdbTxn<()>? = nil) throws -> Bool {
        return try self.was(noteKey: noteKey, seenOnAnyOf: relayUrls.map({ $0.absoluteString }), txn: txn)
    }
    
    func processEvent(_ str: String, originRelayURL: RelayURL? = nil) -> Bool {
        self.process_event(str, originRelayURL: originRelayURL?.absoluteString)
    }
}
