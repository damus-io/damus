//
//  SubscriptionManager.swift
//  damus
//
//  Created by Daniel D’Aquino on 2025-03-25.
//

extension NostrNetworkManager {
    /// Reads or fetches information from RelayPool and NostrDB, and provides an easier and unified higher-level interface.
    ///
    /// ## Implementation notes
    ///
    /// - This class will be a key part of the local relay model migration. Most higher-level code should fetch content from this class, which will properly setup the correct relay pool subscriptions, and provide a stream from NostrDB for higher performance and reliability.
    class SubscriptionManager {
        private let pool: RelayPool
        private var ndb: Ndb
        
        init(pool: RelayPool, ndb: Ndb) {
            self.pool = pool
            self.ndb = ndb
        }
        
        // MARK: - Reading data from Nostr
        
        /// Subscribes to data from the user's relays
        ///
        /// ## Implementation notes
        ///
        /// - When we migrate to the local relay model, we should modify this function to stream directly from NostrDB
        ///
        /// - Parameter filters: The nostr filters to specify what kind of data to subscribe to
        /// - Returns: An async stream of nostr data
        func subscribe(filters: [NostrFilter], to desiredRelays: [RelayURL]? = nil) -> AsyncStream<StreamItem> {
            return AsyncStream<StreamItem> { continuation in
                let ndbStreamTask = Task {
                    do {
                        for await item in try self.ndb.subscribe(filters: try filters.map({ try NdbFilter(from: $0) })) {
                            switch item {
                            case .eose:
                                continuation.yield(.eose)
                            case .event(let noteKey):
                                let lender: NdbNoteLender = { lend in
                                    guard let ndbNoteTxn = self.ndb.lookup_note_by_key(noteKey) else {
                                        throw NdbNoteLenderError.errorLoadingNote
                                    }
                                    guard let unownedNote = UnownedNdbNote(ndbNoteTxn) else {
                                        throw NdbNoteLenderError.errorLoadingNote
                                    }
                                    lend(unownedNote)
                                }
                                continuation.yield(.event(borrow: lender))
                            }
                        }
                    }
                    catch {
                        Log.error("NDB streaming error: %s", for: .ndb, error.localizedDescription)
                    }
                }
                let streamTask = Task {
                    for await _ in self.pool.subscribe(filters: filters, to: desiredRelays) {
                        // NO-OP. Notes will be automatically ingested by NostrDB
                        // TODO: Improve efficiency of subscriptions?
                    }
                }
                continuation.onTermination = { @Sendable _ in
                    streamTask.cancel() // Close the RelayPool stream when caller stops streaming
                    ndbStreamTask.cancel()
                }
            }
        }
    }
    
    enum StreamItem {
        /// An event which can be borrowed from NostrDB
        case event(borrow: NdbNoteLender)
        /// The end of stored events
        case eose
    }
}
