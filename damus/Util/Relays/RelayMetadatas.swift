//
//  RelayMetadatas.swift
//  damus
//
//  Created by William Casarin on 2023-02-09.
//

import Foundation

class RelayMetadatas {
    private var metadata: [String: RelayMetadata] = [:]
    
    func lookup(relay_id: String) -> RelayMetadata? {
        return metadata[relay_id]
    }
    
    func insert(relay_id: String, metadata: RelayMetadata) {
        self.metadata[relay_id] = metadata
    }
}
