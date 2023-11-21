//
//  NotificationService.swift
//  DamusNotificationService
//
//  Created by Daniel D’Aquino on 2023-11-10.
//

import UserNotifications
import Foundation

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        
        let ndb: Ndb? = try? Ndb(owns_db_file: false)
        
        // Modify the notification content here...
        guard let nostrEventInfoDictionary = request.content.userInfo["nostr_event"] as? [AnyHashable: Any],
              let nostrEventInfo = NostrEventInfoFromPushNotification.from(dictionary: nostrEventInfoDictionary) else {
            contentHandler(request.content)
            return;
        }
        
        // Log that we got a push notification
        if let pubkey = Pubkey(hex: nostrEventInfo.pubkey),
           let txn = ndb?.lookup_profile(pubkey) {
            Log.debug("Got push notification from %s (%s)", for: .push_notifications, (txn.unsafeUnownedValue?.profile?.display_name ?? "Unknown"), nostrEventInfo.pubkey)
        }
        
        if let improvedContent = NotificationFormatter.shared.formatMessage(event: nostrEventInfo) {
            contentHandler(improvedContent)
        }
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

}
