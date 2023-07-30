//
//  PresentSheetNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct PresentSheetNotify: Notify {
    typealias Payload = Sheets
    var payload: Payload
}

extension NotifyHandler {
    static var present_sheet: NotifyHandler<PresentSheetNotify> {
        .init()
    }
}

extension Notifications {
    static func present_sheet(_ sheet: Sheets) -> Notifications<PresentSheetNotify> {
        .init(.init(payload: sheet))
    }
}
