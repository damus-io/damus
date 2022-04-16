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
    let unitFlags: NSCalendar.Unit = [.second, .minute, .hour, .day, .weekOfYear, .month, .year]
    let components = (calendar as NSCalendar).components(unitFlags, from: date, to: now, options: [])

    if let year = components.year, year >= 1 {
        return "\(year)yr"
    }

    if let month = components.month, month >= 1 {
        return "\(month)mth"
    }

    if let week = components.weekOfYear, week >= 1 {
        return "\(week)wk"
    }

    if let day = components.day, day >= 1 {
        return "\(day)d"
    }

    if let hour = components.hour, hour >= 1 {
        return "\(hour)h"
    }

    if let minute = components.minute, minute >= 1 {
        return "\(minute)m"
    }

    if let second = components.second, second >= 3 {
        return "\(second)s"
    }

    return "now"
}
