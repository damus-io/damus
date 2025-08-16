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
                let streamTask = Task {
                    for await item in self.pool.subscribe(filters: filters, to: desiredRelays) {
                        switch item {
                        case .eose: continuation.yield(.eose)
                        case .event(let nostrEvent):
                            // At this point of the pipeline, if the note is valid it should have been processed and verified by NostrDB,
                            // in which case we should pull the note from NostrDB to ensure validity.
                            // However, NdbNotes are unowned, so we return a function where our callers can temporarily borrow the NostrDB note
                            let noteId = nostrEvent.id
                            let lender: NdbNoteLender = { lend in
                                guard let ndbNoteTxn = self.ndb.lookup_note(noteId) else {
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
                continuation.onTermination = { @Sendable _ in
                    streamTask.cancel() // Close the RelayPool stream when caller stops streaming
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
