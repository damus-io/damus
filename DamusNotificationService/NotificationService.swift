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
        guard let nostrEventJSON = request.content.userInfo["nostr_event"] as? String,
              let nostrEvent = NdbNote.owned_from_json(json: nostrEventJSON)
        else {
            contentHandler(request.content)
            return;
        }
        
        // Log that we got a push notification
        if let txn = ndb?.lookup_profile(nostrEvent.pubkey) {
            Log.debug("Got push notification from %s (%s)", for: .push_notifications, (txn.unsafeUnownedValue?.profile?.display_name ?? "Unknown"), nostrEvent.pubkey.hex())
        }
        
        if let improvedContent = NotificationFormatter.shared.format_message(event: nostrEvent, ndb: ndb) {
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
