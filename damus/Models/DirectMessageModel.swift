//
//  DirectMessageModel.swift
//  damus
//
//  Created by William Casarin on 2022-07-03.
//

import Foundation

class DirectMessageModel: ObservableObject {
    @Published var events: [NostrEvent]
    
    init(events: [NostrEvent]) {
        self.events = events
    }
    
    init() {
        self.events = []
    }
}
