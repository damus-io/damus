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
    func subscribe(filters: [NostrFilter], maxSimultaneousResults: Int = 1000) throws(NdbStreamError) -> AsyncStream<StreamItem> {
        let filtersPointer = UnsafeMutablePointer<ndb_filter>.allocate(capacity: filters.count)
        for (index, filter) in filters.enumerated() {
            do {
                let filterPointer = try filter.toNdbFilter()
                filtersPointer.advanced(by: index).pointee = filterPointer.pointee
                filterPointer.deallocate()
            }
            catch {
                throw .cannotConvertFilter(error)
            }
        }
        
        // Fetch initial results
        guard let txn = NdbTxn(ndb: self) else { throw .cannotOpenTransaction }
        let count = UnsafeMutablePointer<Int32>.allocate(capacity: 1)
        let results = UnsafeMutablePointer<ndb_query_result>.allocate(capacity: maxSimultaneousResults)
        guard ndb_query(&txn.txn, filtersPointer,  Int32(filters.count), results, Int32(maxSimultaneousResults), count) == 1 else {
            throw .initialQueryFailed
        }
        
        return AsyncStream<StreamItem> { continuation in
            var streaming = true
            continuation.onTermination = { @Sendable _ in
                print("ndb_wait: stream: Terminated early")
                streaming = false
            }
            
            // Stream all results already present in the database
            for i in 0..<count.pointee {
                continuation.yield(.event(results.advanced(by: Int(i)).pointee.note_id))
            }
            count.deallocate()
            results.deallocate()
            
            // Indicate this is the end of the results currently present in the database
            continuation.yield(.eose)
            
            if !streaming {
                return
            }
            
            // Stream new results
            let subid = ndb_subscribe(self.ndb.ndb, filtersPointer, Int32(filters.count))
            
            // Set the subscription callback
            self.setCallback(for: subid, callback: { noteKey in
                continuation.yield(.event(noteKey))
            })
            
            // On termination, cancel the subscription and cleanup.
            continuation.onTermination = { @Sendable _ in
                print("ndb_wait: stream: Terminated")
                streaming = false
                ndb_unsubscribe(self.ndb.ndb, subid)
                self.unsetCallback(subscriptionId: subid)
                filtersPointer.deallocate()
            }
        }
    }
    
    private func waitWithoutTimeout(for noteId: NoteId) async throws(NdbLookupError) -> NdbTxn<NdbNote>? {
        do {
            for try await item in try self.subscribe(filters: [NostrFilter(ids: [noteId])]) {
                switch item {
                case .eose:
                    continue
                case .event(let noteKey):
                    guard let txn = NdbTxn(ndb: self) else { throw NdbLookupError.cannotOpenTransaction }
                    guard let note = self.lookup_note_by_key_with_txn(noteKey, txn: txn) else { throw NdbLookupError.internalInconsistency }
                    if note.id == noteId {
                        Log.debug("ndb wait: %d has matching id %s. Returning transaction", for: .ndb, noteKey, noteId.hex())
                        return NdbTxn<NdbNote>.pure(ndb: self, val: note)
                    }
                }
            }
        }
        catch {
            if let error = error as? NdbStreamError { throw NdbLookupError.streamError(error) }
            else if let error = error as? NdbLookupError { throw error }
            else { throw .internalInconsistency }
        }
        return nil
    }
    
    func waitFor(noteId: NoteId, timeout: TimeInterval = 10) async throws(NdbLookupError) -> NdbTxn<NdbNote>? {
        do {
            return try await withCheckedThrowingContinuation({ continuation in
                var done = false
                let waitTask = Task {
                    do {
                        print("ndb_wait: Waiting for \(noteId.hex())")
                        let result = try await self.waitWithoutTimeout(for: noteId)
                        if !done {
                            print("ndb_wait: Found \(noteId.hex())")
                            continuation.resume(returning: result)
                            done = true
                        }
                    }
                    catch {
                        if !done {
                            print("ndb_wait: Error on \(noteId.hex()): \(error.localizedDescription)")
                            continuation.resume(throwing: error)
                            done = true
                        }
                    }
                }
                
                let timeoutTask = Task {
                    try await Task.sleep(for: .seconds(Int(timeout)))
                    if !done {
                        print("ndb_wait: Timeout on \(noteId.hex()). Cancelling wait task…")
                        done = true
                        print("ndb_wait: throwing timeout error")
                        continuation.resume(throwing: NdbLookupError.timeout)
                    }
                    // waitTask.cancel()
                }
            })
        }
        catch {
            if let error = error as? NdbLookupError { throw error }
            else { throw .internalInconsistency }
        }
    }
}
