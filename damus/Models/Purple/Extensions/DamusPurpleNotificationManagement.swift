//
//  DamusPurpleNotificationManagement.swift
//  damus
//
//  Created by Daniel D’Aquino on 2024-02-26.
//

import Foundation

/// A definition of how many days in advance to notify the user of impending expiration. (e.g. 3 days before expiration AND 2 days before expiration AND 1 day before expiration)
fileprivate let PURPLE_IMPENDING_EXPIRATION_NOTIFICATION_SCHEDULE: Set<Int> = [7, 3, 1]
fileprivate let ONE_DAY: TimeInterval = 60 * 60 * 24

extension DamusPurple {
    typealias NotificationHandlerFunction = (DamusAppNotification) async -> Void
    
    func check_and_send_app_notifications_if_needed(handler: NotificationHandlerFunction) async {
        await self.check_and_send_purple_expiration_notifications_if_needed(handler: handler)
    }
    
    /// Checks if we need to send a DamusPurple impending expiration notification to the user, and sends them if needed.
    ///
    /// **Note:** To keep things simple at this point, this function uses a "best effort" strategy, and silently fails if something is wrong, as it is not an essential component of the app — to avoid adding more error handling complexity to the app
    private func check_and_send_purple_expiration_notifications_if_needed(handler: NotificationHandlerFunction) async {
        if self.storekit_manager.recorded_purchased_products.count > 0 {
            // If user has a recurring IAP purchase, there no need to notify them of impending expiration
            return
        }
        guard let purple_expiration_date: Date = try? await self.get_maybe_cached_account(pubkey: self.keypair.pubkey)?.expiry else {
            return  // If there are no expiry dates (e.g. The user is not a Purple user) or we cannot get it for some reason (e.g. server is temporarily down and we have no cache), don't bother sending notifications
        }
        
        let days_to_expiry: Int = round_days_to_date(purple_expiration_date, from: Date.now)
        
        let applicable_impending_expiry_notification_schedule_items: [Int] = PURPLE_IMPENDING_EXPIRATION_NOTIFICATION_SCHEDULE.filter({ $0 >= days_to_expiry })
        
        for applicable_impending_expiry_notification_schedule_item in applicable_impending_expiry_notification_schedule_items {
            // Send notifications predicted by the schedule
            // Note: The `insert_app_notification` has built-in logic to prevent us from sending two identical notifications, so we need not worry about it here.
            await handler(.init(
                content: .purple_impending_expiration(
                    days_remaining: applicable_impending_expiry_notification_schedule_item,
                    expiry_date: UInt64(purple_expiration_date.timeIntervalSince1970)
                ),
                timestamp: purple_expiration_date.addingTimeInterval(-Double(applicable_impending_expiry_notification_schedule_item) * ONE_DAY))
            )
        }
        
        if days_to_expiry < 0 {
            await handler(.init(
                content: .purple_expired(expiry_date: UInt64(purple_expiration_date.timeIntervalSince1970)),
                timestamp: purple_expiration_date)
            )
        }
    }
}

fileprivate func round_days_to_date(_ target_date: Date, from from_date: Date) -> Int {
    return Int(round(target_date.timeIntervalSince(from_date) / ONE_DAY))
}
