//
//  DamusDuration.swift
//  damus
//
//  Created by Charlie Fish on 1/13/24.
//

import Foundation

enum DamusDuration: CaseIterable {
    case indefinite
    case day
    case week
    case month

    var title: String {
        switch self {
        case .indefinite:
            return NSLocalizedString("Indefinite", comment: "Mute a given item indefinitly (until user unmutes it). As opposed to muting the item for a given period of time.")
        case .day:
            return NSLocalizedString("24 hours", comment: "A duration of 24 hours/1 day to be shown to the user. Most likely in the context of how long they want to mute a piece of content for.")
        case .week:
            return NSLocalizedString("1 week", comment: "A duration of 1 week to be shown to the user. Most likely in the context of how long they want to mute a piece of content for.")
        case .month:
            return NSLocalizedString("1 month", comment: "A duration of 1 month to be shown to the user. Most likely in the context of how long they want to mute a piece of content for.")
        }
    }

    var date_from_now: Date? {
        let current_date = Date()

        switch self {
        case .indefinite:
            return nil
        case .day:
            return Calendar.current.date(byAdding: .day, value: 1, to: current_date)
        case .week:
            return Calendar.current.date(byAdding: .day, value: 7, to: current_date)
        case .month:
            return Calendar.current.date(byAdding: .month, value: 1, to: current_date)
        }
    }
}
