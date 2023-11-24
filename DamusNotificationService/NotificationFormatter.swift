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
    
    // MARK: - Formatting with NdbNote
    
    // TODO: Prepare a `LocalNotification` object from `NdbNote` to reuse Notification formatting code from Local notifications
    func format_message(event: NdbNote, ndb: Ndb?) -> UNMutableNotificationContent? {
        guard let txn = ndb?.lookup_profile(event.pubkey),
              let display_name = txn.unsafeUnownedValue?.profile?.display_name
        else {
            return self.format_message(event: event)
        }
        
        return self.format_message(event: event, display_name: display_name)
    }
    
    func format_message(event: NdbNote, display_name: String) -> UNMutableNotificationContent? {
        guard let best_attempt_content: UNMutableNotificationContent = self.format_message(event: event) else { return nil }
        
        switch event.known_kind {
            case .text:
                best_attempt_content.title = String(format: NSLocalizedString("%@ posted a note", comment: "Title label for push notification where a user posted a note"), display_name)
                break
            case .dm:
                best_attempt_content.title = String(format: NSLocalizedString("New message from %@", comment: "Title label for push notifications where a direct message was sent to the user"), display_name)
                break
            case .like:
                guard let reaction_emoji = to_reaction_emoji(ev: event) else {
                    best_attempt_content.title = String(format: NSLocalizedString("%@ reacted to your note", comment: "Reaction heading in local/push notification"), display_name)
                    best_attempt_content.body = ""
                    break
                }
                best_attempt_content.title = String(format: NSLocalizedString("%@ reacted with %@", comment: "Reacted by heading in local notification"), display_name, reaction_emoji)
                best_attempt_content.body = ""
                break
            case .zap:
                best_attempt_content.title = String(format: NSLocalizedString("%@ zapped you ⚡️", comment: "Title label for a push notification where someone zapped the user"), display_name)
                break
            default:
                return nil
        }
        
        return best_attempt_content
    }
    
    func format_message(event: NdbNote) -> UNMutableNotificationContent? {
        let content = UNMutableNotificationContent()
        if let event_json_data = try? JSONEncoder().encode(event),  // Must be encoded, as the notification completion handler requires this object to conform to `NSSecureCoding`
           let event_json_string = String(data: event_json_data, encoding: .utf8) {
            content.userInfo = [
                NDB_NOTE_JSON_USER_INFO_KEY: event_json_string
            ]
        }
        switch event.known_kind {
            case .text:
                content.title = NSLocalizedString("Someone posted a note", comment: "Title label for push notification where someone posted a note")
                content.body = event.content
                break
            case .dm:
                content.title = NSLocalizedString("New message", comment: "Title label for push notifications where a direct message was sent to the user")
                content.body = NSLocalizedString("(Contents are encrypted)", comment: "Label on push notification indicating that the contents of the message are encrypted")
                break
            case .like:
                guard let reactionEmoji = to_reaction_emoji(ev: event) else {
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
    
    // MARK: - Formatting with LocalNotification
    
    func format_message(displayName: String, notify: LocalNotification) -> (content: UNMutableNotificationContent, identifier: String) {
        let content = UNMutableNotificationContent()
        var title = ""
        var identifier = ""
        
        switch notify.type {
            case .mention:
                title = String(format: NSLocalizedString("Mentioned by %@", comment: "Mentioned by heading in local notification"), displayName)
                identifier = "myMentionNotification"
            case .repost:
                title = String(format: NSLocalizedString("Reposted by %@", comment: "Reposted by heading in local notification"), displayName)
                identifier = "myBoostNotification"
            case .like:
                title = String(format: NSLocalizedString("%@ reacted with %@", comment: "Reacted by heading in local notification"), displayName, to_reaction_emoji(ev: notify.event) ?? "")
                identifier = "myLikeNotification"
            case .dm:
                title = displayName
                identifier = "myDMNotification"
            case .zap, .profile_zap:
                // not handled here
                break
        }
        content.title = title
        content.body = notify.content
        content.sound = UNNotificationSound.default
        content.userInfo = notify.to_lossy().to_user_info()

        return (content, identifier)
    }
}
