//
//  RelayModel.swift
//  damus
//
//  Created by Bryan Montz on 6/10/23.
//

import Foundation

final class RelayModel: Hashable {
    
    let url: RelayURL
    let log: RelayLog
    let metadata: RelayMetadata

    init(_ url: RelayURL, metadata: RelayMetadata) {
        self.url = url
        self.log = RelayLog(url.url)
        self.metadata = metadata
    }
    
    static func == (lhs: RelayModel, rhs: RelayModel) -> Bool {
        lhs.url == rhs.url
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
    }
}
