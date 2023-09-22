//
//  ReportNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct ReportNotify: Notify {
    typealias Payload = ReportTarget
    var payload: ReportTarget
}

extension NotifyHandler {
    static var report: NotifyHandler<ReportNotify> {
        .init()
    }
}

extension Notifications {
    static func report(_ target: ReportTarget) -> Notifications<ReportNotify> {
        .init(.init(payload: target))
    }
}
