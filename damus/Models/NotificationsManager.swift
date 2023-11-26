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

func process_local_notification(state: HeadlessDamusState, event ev: NostrEvent) {
    guard should_display_notification(state: state, event: ev) else {
        // We should not display notification. Exit.
        return
    }

    guard let local_notification = generate_local_notification_object(from: ev, state: state) else {
        return
    }
    create_local_notification(profiles: state.profiles, notify: local_notification)
}

func should_display_notification(state: HeadlessDamusState, event ev: NostrEvent) -> Bool {
    if ev.known_kind == nil {
        return false
    }

    if state.settings.notification_only_from_following,
       state.contacts.follow_state(ev.pubkey) != .follows
        {
        return false
    }

    // Don't show notifications from muted threads.
    if state.muted_threads.isMutedThread(ev, keypair: state.keypair) {
        return false
    }
    
    // Don't show notifications for old events
    guard ev.age < EVENT_MAX_AGE_FOR_NOTIFICATION else {
        return false
    }
    
    return true
}

func generate_local_notification_object(from ev: NostrEvent, state: HeadlessDamusState) -> LocalNotification? {
    guard let type = ev.known_kind else {
        return nil
    }
    
    if type == .text, state.settings.mention_notification {
        let blocks = ev.blocks(state.keypair).blocks
        for case .mention(let mention) in blocks {
            guard case .pubkey(let pk) = mention.ref, pk == state.keypair.pubkey else {
                continue
            }
            let content_preview = render_notification_content_preview(ev: ev, profiles: state.profiles, keypair: state.keypair)
            return LocalNotification(type: .mention, event: ev, target: ev, content: content_preview)
        }
    } else if type == .boost,
              state.settings.repost_notification,
              let inner_ev = ev.get_inner_event()
    {
        let content_preview = render_notification_content_preview(ev: inner_ev, profiles: state.profiles, keypair: state.keypair)
        return LocalNotification(type: .repost, event: ev, target: inner_ev, content: content_preview)
    } else if type == .like,
              state.settings.like_notification,
              let evid = ev.referenced_ids.last,
              let liked_event = state.ndb.lookup_note(evid).unsafeUnownedValue   // We are only accessing it temporarily to generate notification content
    {
        let content_preview = render_notification_content_preview(ev: liked_event, profiles: state.profiles, keypair: state.keypair)
        return LocalNotification(type: .like, event: ev, target: liked_event, content: content_preview)
    }
    else if type == .dm,
            state.settings.dm_notification {
        let convo = ev.decrypted(keypair: state.keypair) ?? NSLocalizedString("New encrypted direct message", comment: "Notification that the user has received a new direct message")
        return LocalNotification(type: .dm, event: ev, target: ev, content: convo)
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
