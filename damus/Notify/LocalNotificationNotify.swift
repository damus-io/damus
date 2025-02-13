//
//  LocalNotificationNotify.swift
//  damus
//
//  Created by William Casarin on 2023-07-30.
//

import Foundation

extension QueueableNotify<LossyLocalNotification> {
    /// A shared singleton for opening local and push user notifications
    ///
    /// ## Implementation notes
    ///
    /// - The queue can only hold one element. This is done because if the user hypothetically opened 10 push notifications and there was a lag, we wouldn't want the app to suddenly open 10 different things.
    static let shared = QueueableNotify(maxQueueItems: 1)
}
