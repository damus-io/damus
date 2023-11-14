//
//  NotificationFormatter.swift
//  DamusNotificationService
//
//  Created by Daniel D’Aquino on 2023-11-13.
//

import Foundation
import UserNotifications

struct NotificationFormatter {
    static var shared = NotificationFormatter()
    
    // TODO: These is a very generic notification formatter. Once we integrate NostrDB into the extension, we should reuse various functions present in `HomeModel.swift`
    func formatMessage(event: NostrEventInfoFromPushNotification) -> UNNotificationContent? {
        let content = UNMutableNotificationContent()
        if let event_json_data = try? JSONEncoder().encode(event),  // Must be encoded, as the notification completion handler requires this object to conform to `NSSecureCoding`
           let event_json_string = String(data: event_json_data, encoding: .utf8) {
            content.userInfo = [
                "nostr_event_info": event_json_string
            ]
        }
        switch event.kind {
            case .text:
                content.title = NSLocalizedString("Someone posted a note", comment: "Title label for push notification where someone posted a note")
                content.body = event.content
                break
            case .dm:
                content.title = NSLocalizedString("New message", comment: "Title label for push notifications where a direct message was sent to the user")
                content.body = NSLocalizedString("(Contents are encrypted)", comment: "Label on push notification indicating that the contents of the message are encrypted")
                break
            case .like:
                guard let reactionEmoji = event.reactionEmoji() else {
                    content.title = NSLocalizedString("Someone reacted to your note", comment: "Generic title label for push notifications where someone reacted to the user's post")
                    break
                }
                content.title = NSLocalizedString("New note reaction", comment: "Title label for push notifications where someone reacted to the user's post with a specific emoji")
                content.body = String(format: NSLocalizedString("Someone reacted to your note with %@", comment: "Body label for push notifications where someone reacted to the user's post with a specific emoji"), reactionEmoji)
                break
            case .zap:
                content.title = NSLocalizedString("Someone zapped you ⚡️", comment: "Title label for a push notification where someone zapped the user")
                break
            default:
                return nil
        }
        return content
    }
}
