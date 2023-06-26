//
//  NotificationStatusModel.swift
//  damus
//
//  Created by William Casarin on 2023-06-23.
//

import Foundation

class NotificationStatusModel: ObservableObject {
    @Published var new_events: NewEventsBits = NewEventsBits()
}
