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
    
    func format_message(displayName: String, notify: LocalNotification) -> (content: UNMutableNotificationContent, identifier: String)? {
        let content = UNMutableNotificationContent()
        var title = ""
        var identifier = ""
        
        switch notify.type {
            case .tagged:
                title = String(format: NSLocalizedString("Tagged by %@", comment: "Tagged by heading in local notification"), displayName)
                identifier = "myMentionNotification"
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
                // not handled here. Try `format_message(displayName: String, notify: LocalNotification, state: HeadlessDamusState) async -> (content: UNMutableNotificationContent, identifier: String)?`
                return nil
            case .reply:
                title = String(format: NSLocalizedString("%@ replied to your note", comment: "Heading for local notification indicating a new reply"), displayName)
                identifier = "myReplyNotification"
        }
        content.title = title
        content.body = notify.content
        content.sound = UNNotificationSound.default
        content.userInfo = notify.to_lossy().to_user_info()

        return (content, identifier)
    }
    
    func format_message(displayName: String, notify: LocalNotification, state: HeadlessDamusState) async -> (content: UNMutableNotificationContent, identifier: String)? {
        // Try sync method first and return if it works
        if let sync_formatted_message = self.format_message(displayName: displayName, notify: notify) {
            return sync_formatted_message
        }
        
        // If it does not work, try async formatting methods
        let content = UNMutableNotificationContent()

        switch notify.type {
            case .zap, .profile_zap:
                guard let zap = await get_zap(from: notify.event, state: state) else {
                    Log.debug("format_message: async get_zap failed", for: .push_notifications)
                    return nil
                }
                content.title = Self.zap_notification_title(zap)
                content.body = Self.zap_notification_body(profiles: state.profiles, zap: zap)
                content.sound = UNNotificationSound.default
                content.userInfo = LossyLocalNotification(type: .zap, mention: .init(nip19: .note(notify.event.id))).to_user_info()
                return (content, "myZapNotification")
            default:
                // The sync method should have taken care of this.
                return nil
        }
    }
    
    // MARK: - Formatting zap utility notifications

    static func zap_notification_title(_ zap: Zap) -> String {
        if zap.private_request != nil {
            return NSLocalizedString("Private Zap", comment: "Title of notification when a private zap is received.")
        } else {
            return NSLocalizedString("Zap", comment: "Title of notification when a non-private zap is received.")
        }
    }

    static func zap_notification_body(profiles: Profiles, zap: Zap, locale: Locale = Locale.current) -> String {
        let src = zap.request.ev
        let pk = zap.is_anon ? ANON_PUBKEY : src.pubkey

        let profile_txn = profiles.lookup(id: pk)
        let profile = profile_txn?.unsafeUnownedValue
        let name = Profile.displayName(profile: profile, pubkey: pk).displayName.truncate(maxLength: 50)

        let sats = NSNumber(value: (Double(zap.invoice.amount) / 1000.0))
        let formattedSats = format_msats_abbrev(zap.invoice.amount)

        if src.content.isEmpty {
            let format = localizedStringFormat(key: "zap_notification_no_message", locale: locale)
            return String(format: format, locale: locale, sats.decimalValue as NSDecimalNumber, formattedSats, name)
        } else {
            let format = localizedStringFormat(key: "zap_notification_with_message", locale: locale)
            return String(format: format, locale: locale, sats.decimalValue as NSDecimalNumber, formattedSats, name, src.content)
        }
    }
}
