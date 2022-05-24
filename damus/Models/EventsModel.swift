//
//  EventsModel.swift
//  damus
//
//  Created by William Casarin on 2022-05-24.
//

import Foundation


class EventsModel: ObservableObject {
    var has_event: Set<String> = Set()
    @Published var events: [NostrEvent] = []
    
    init() {
    }
}
