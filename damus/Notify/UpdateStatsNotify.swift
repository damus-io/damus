//
//  UpdateStatsNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

struct UpdateStatsNotify: Notify {
    typealias Payload = NoteId
    var payload: Payload
}

extension NotifyHandler {
    static var update_stats: NotifyHandler<UpdateStatsNotify> {
        .init()
    }
}

extension Notifications {
    static func update_stats(note_id: NoteId) -> Notifications<UpdateStatsNotify> {
        .init(.init(payload: note_id))
    }
}

