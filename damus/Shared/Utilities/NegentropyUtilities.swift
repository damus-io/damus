//
//  NegentropyUtilities.swift
//  damus
//
//  Created by Daniel D'Aquino on 2026-01-15.
//

import Negentropy

extension NegentropyStorageVector {
    func insert(nostrEvent: NostrEvent) throws {
        try self.insert(timestamp: UInt64(nostrEvent.created_at), id: Id(data: nostrEvent.id.id))
    }
    
    func insert(nostrEvent: borrowing UnownedNdbNote) throws {
        try self.insert(timestamp: UInt64(nostrEvent.createdAt), id: Id(data: nostrEvent.id.id))
    }
    
    func unsealAndInsert(nostrEvent: NostrEvent) {
        self.unseal()
        try? self.insert(nostrEvent: nostrEvent)
    }
    
    func unsealAndInsert(nostrEvent: borrowing UnownedNdbNote) {
        self.unseal()
        try? self.insert(nostrEvent: nostrEvent)
    }
}
