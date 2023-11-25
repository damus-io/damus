//
//  NotificationsManager.swift
//  damus
//
//  Handles several aspects of notification logic (Both local and push notifications)
//
//  Created by Daniel D’Aquino on 2023-11-24.
//

import Foundation
import UIKit

let EVENT_MAX_AGE_FOR_NOTIFICATION: TimeInterval = 12 * 60 * 60

func process_local_notification(ndb: Ndb, settings: UserSettingsStore, contacts: Contacts, muted_threads: MutedThreadsManager, user_keypair: Keypair, profiles: Profiles, event ev: NostrEvent) {
    if ev.known_kind == nil {
        return
    }

    if settings.notification_only_from_following,
       contacts.follow_state(ev.pubkey) != .follows
        {
        return
    }

    // Don't show notifications from muted threads.
    if muted_threads.isMutedThread(ev, keypair: user_keypair) {
        return
    }
    
    // Don't show notifications for old events
    guard ev.age < EVENT_MAX_AGE_FOR_NOTIFICATION else {
        return
    }

    guard let local_notification = generate_local_notification_object(
        ndb: ndb,
        from: ev,
        settings: settings,
        user_keypair: user_keypair,
        profiles: profiles
    ) else {
        return
    }
    create_local_notification(profiles: profiles, notify: local_notification)
}


func generate_local_notification_object(ndb: Ndb, from ev: NostrEvent, settings: UserSettingsStore, user_keypair: Keypair, profiles: Profiles) -> LocalNotification? {
    guard let type = ev.known_kind else {
        return nil
    }
    
    if type == .text, settings.mention_notification {
        let blocks = ev.blocks(user_keypair).blocks
        for case .mention(let mention) in blocks {
            guard case .pubkey(let pk) = mention.ref, pk == user_keypair.pubkey else {
                continue
            }
            let content_preview = render_notification_content_preview(ev: ev, profiles: profiles, keypair: user_keypair)
            return LocalNotification(type: .mention, event: ev, target: ev, content: content_preview)
        }
    } else if type == .boost,
              settings.repost_notification,
              let inner_ev = ev.get_inner_event()
    {
        let content_preview = render_notification_content_preview(ev: inner_ev, profiles: profiles, keypair: user_keypair)
        return LocalNotification(type: .repost, event: ev, target: inner_ev, content: content_preview)
    } else if type == .like,
              settings.like_notification,
              let evid = ev.referenced_ids.last,
              let liked_event = ndb.lookup_note(evid).unsafeUnownedValue   // We are only accessing it temporarily to generate notification content
    {
        let content_preview = render_notification_content_preview(ev: liked_event, profiles: profiles, keypair: user_keypair)
        return LocalNotification(type: .like, event: ev, target: liked_event, content: content_preview)
    }
    
    return nil
}

func create_local_notification(profiles: Profiles, notify: LocalNotification) {
    let displayName = event_author_name(profiles: profiles, pubkey: notify.event.pubkey)
    
    let (content, identifier) = NotificationFormatter.shared.format_message(displayName: displayName, notify: notify)

    let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 1, repeats: false)

    let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)

    UNUserNotificationCenter.current().add(request) { error in
        if let error = error {
            print("Error: \(error)")
        } else {
            print("Local notification scheduled")
        }
    }
}

func render_notification_content_preview(ev: NostrEvent, profiles: Profiles, keypair: Keypair) -> String {

    let prefix_len = 300
    let artifacts = render_note_content(ev: ev, profiles: profiles, keypair: keypair)

    // special case for longform events
    if ev.known_kind == .longform {
        let longform = LongformEvent(event: ev)
        return longform.title ?? longform.summary ?? "Longform Event"
    }
    
    switch artifacts {
    case .longform:
        // we should never hit this until we have more note types built out of parts
        // since we handle this case above in known_kind == .longform
        return String(ev.content.prefix(prefix_len))
        
    case .separated(let artifacts):
        return String(NSAttributedString(artifacts.content.attributed).string.prefix(prefix_len))
    }
}

func event_author_name(profiles: Profiles, pubkey: Pubkey) -> String {
    return profiles.lookup(id: pubkey).map({ profile in
        Profile.displayName(profile: profile, pubkey: pubkey).username.truncate(maxLength: 50)
    }).value
}
