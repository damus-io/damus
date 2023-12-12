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
        
        guard let nostr_event_json = request.content.userInfo["nostr_event"] as? String,
              let nostr_event = NdbNote.owned_from_json(json: nostr_event_json)
        else {
            // No nostr event detected. Just display the original notification
            contentHandler(request.content)
            return;
        }
        
        // Log that we got a push notification
        Log.debug("Got nostr event push notification from pubkey %s", for: .push_notifications, nostr_event.pubkey.hex())
        
        guard let state = NotificationExtensionState(),
              let display_name = state.ndb.lookup_profile(nostr_event.pubkey)?.unsafeUnownedValue?.profile?.display_name  // We are not holding the txn here.
        else {
            // Something failed to initialize so let's go for the next best thing
            guard let improved_content = NotificationFormatter.shared.format_message(event: nostr_event) else {
                // We cannot format this nostr event. Suppress notification.
                contentHandler(UNNotificationContent())
                return
            }
            contentHandler(improved_content)
            return
        }
        
        guard should_display_notification(state: state, event: nostr_event) else {
            // We should not display notification for this event. Suppress notification.
            contentHandler(UNNotificationContent())
            return
        }
        
        guard let notification_object = generate_local_notification_object(from: nostr_event, state: state) else {
            // We could not process this notification. Probably an unsupported nostr event kind. Suppress.
            contentHandler(UNNotificationContent())
            return
        }
        
        Task {
            if let (improvedContent, _) = await NotificationFormatter.shared.format_message(displayName: display_name, notify: notification_object, state: state) {
                contentHandler(improvedContent)
            }
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
