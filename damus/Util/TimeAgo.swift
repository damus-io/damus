//
//  TimeAgo.swift
//  damus
//
//  Created by William Casarin on 2022-04-16.
//

import Foundation

public func time_ago_since(_ date: Date) -> String {

    let calendar = Calendar.current
    let now = Date()
    let unitFlags: NSCalendar.Unit = [.second, .minute, .hour, .day, .weekOfMonth, .month, .year]

    let components = (calendar as NSCalendar).components(unitFlags, from: date, to: now, options: [])

    let formatter = DateComponentsFormatter()
    formatter.unitsStyle = .abbreviated
    formatter.maximumUnitCount = 1
    formatter.allowedUnits = unitFlags

    // Manually format date component from only the most significant time unit because
    // DateComponentsFormatter rounds up by default.

    if let year = components.year, year >= 1 {
        return formatter.string(from: DateComponents(calendar: calendar, year: year))!
    }

    if let month = components.month, month >= 1 {
        return formatter.string(from: DateComponents(calendar: calendar, month: month))!
    }

    if let week = components.weekOfMonth, week >= 1 {
        return formatter.string(from: DateComponents(calendar: calendar, weekOfMonth: week))!
    }

    if let day = components.day, day >= 1 {
        return formatter.string(from: DateComponents(calendar: calendar, day: day))!
    }

    if let hour = components.hour, hour >= 1 {
        return formatter.string(from: DateComponents(calendar: calendar, hour: hour))!
    }

    if let minute = components.minute, minute >= 1 {
        return formatter.string(from: DateComponents(calendar: calendar, minute: minute))!
    }

    if let second = components.second, second >= 3 {
        return formatter.string(from: DateComponents(calendar: calendar, second: second))!
    }

    return NSLocalizedString("now", comment: "String indicating that a given timestamp just occurred")
}
