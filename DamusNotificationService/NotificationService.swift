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
        
        // Don't show notification details that match mute list.
        // TODO: Remove this code block once we get notification suppression entitlement from Apple. It will be covered by the `guard should_display_notification` block
        if state.mutelist_manager.is_event_muted(nostr_event) {
            // We cannot really suppress muted notifications until we have the notification supression entitlement.
            // The best we can do if we ever get those muted notifications (which we generally won't due to server-side processing) is to obscure the details
            let content = UNMutableNotificationContent()
            content.title = NSLocalizedString("Muted event", comment: "Title for a push notification which has been muted")
            content.body = NSLocalizedString("This is an event that has been muted according to your mute list rules. We cannot suppress this notification, but we obscured the details to respect your preferences", comment: "Description for a push notification which has been muted, and explanation that we cannot suppress it")
            content.sound = UNNotificationSound.default
            contentHandler(content)
            return
        }
        
        guard should_display_notification(state: state, event: nostr_event, mode: .push) else {
            // We should not display notification for this event. Suppress notification.
            // contentHandler(UNNotificationContent())
            // TODO: We cannot really suppress until we have the notification supression entitlement. Show the raw notification
            contentHandler(request.content)
            return
        }
        
        guard let notification_object = generate_local_notification_object(from: nostr_event, state: state) else {
            // We could not process this notification. Probably an unsupported nostr event kind. Suppress.
            // contentHandler(UNNotificationContent())
            // TODO: We cannot really suppress until we have the notification supression entitlement. Show the raw notification
            contentHandler(request.content)
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
