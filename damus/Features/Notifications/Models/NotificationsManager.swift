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
    guard should_display_notification(state: state, event: ev, mode: .local) else {
        // We should not display notification. Exit.
        return
    }

    guard let local_notification = generate_local_notification_object(ndb: state.ndb, from: ev, state: state) else {
        return
    }

    create_local_notification(profiles: state.profiles, notify: local_notification)
}

func should_display_notification(state: HeadlessDamusState, event ev: NostrEvent, mode: UserSettingsStore.NotificationsMode) -> Bool {
    // Do not show notification if it's coming from a mode different from the one selected by our user
    guard state.settings.notification_mode == mode else {
        return false
    }
    
    if ev.known_kind == nil {
        return false
    }

    if state.settings.notification_only_from_following,
       state.contacts.follow_state(ev.pubkey) != .follows
        {
        return false
    }

    if state.settings.hellthread_notifications_disabled && ev.is_hellthread(max_pubkeys: state.settings.hellthread_notification_max_pubkeys) {
        return false
    }

    // Don't show notifications that match mute list.
    if state.mutelist_manager.is_event_muted(ev) {
        return false
    }

    // Don't show notifications for old events
    guard ev.age < EVENT_MAX_AGE_FOR_NOTIFICATION else {
        return false
    }

    // Don't show notifications for future events.
    // Allow notes that are created no more than 3 seconds in the future
    // to account for natural clock skew between sender and receiver.
    guard ev.age >= -3 else {
        return false
    }

    return true
}

func generate_local_notification_object(ndb: Ndb, from ev: NostrEvent, state: HeadlessDamusState) -> LocalNotification? {
    guard let type = ev.known_kind else {
        return nil
    }
    
    if type == .text,
       state.settings.mention_notification,
       let blocks = ev.blocks(ndb: ndb)?.unsafeUnownedValue
    {
        for case .mention(let mention) in blocks.iter(note: ev) {
            guard case .npub = mention.bech32_type,
                  (memcmp(state.keypair.pubkey.id.bytes, mention.bech32.npub.pubkey, 32) == 0) else {
                continue
            }
            let content_preview = render_notification_content_preview(ndb: ndb, ev: ev, profiles: state.profiles, keypair: state.keypair)
            return LocalNotification(type: .mention, event: ev, target: .note(ev), content: content_preview)
        }

        if ev.referenced_ids.contains(where: { note_id in
            guard let note_author: Pubkey = state.ndb.lookup_note(note_id)?.unsafeUnownedValue?.pubkey else { return false }
            guard note_author == state.keypair.pubkey else { return false }
            return true
        }) {
            // This is a reply to one of our posts
            let content_preview = render_notification_content_preview(ndb: state.ndb, ev: ev, profiles: state.profiles, keypair: state.keypair)
            return LocalNotification(type: .reply, event: ev, target: .note(ev), content: content_preview)
        }

        if ev.referenced_pubkeys.contains(state.keypair.pubkey) {
            // not mentioned or replied to, just tagged
            let content_preview = render_notification_content_preview(ndb: state.ndb, ev: ev, profiles: state.profiles, keypair: state.keypair)
            return LocalNotification(type: .tagged, event: ev, target: .note(ev), content: content_preview)
        }

    } else if type == .boost,
              state.settings.repost_notification,
              let inner_ev = ev.get_inner_event()
    {
        let content_preview = render_notification_content_preview(ndb: ndb, ev: inner_ev, profiles: state.profiles, keypair: state.keypair)
        return LocalNotification(type: .repost, event: ev, target: .note(inner_ev), content: content_preview)
    } else if type == .like, state.settings.like_notification, let evid = ev.referenced_ids.last {
        if let txn = state.ndb.lookup_note(evid, txn_name: "local_notification_like"),
           let liked_event = txn.unsafeUnownedValue
        {
           let content_preview = render_notification_content_preview(ndb: ndb, ev: liked_event, profiles: state.profiles, keypair: state.keypair)
            return LocalNotification(type: .like, event: ev, target: .note(liked_event), content: content_preview)
        } else {
            return LocalNotification(type: .like, event: ev, target: .note_id(evid), content: "")
        }
    }
    else if type == .dm,
            state.settings.dm_notification {
        let convo = ev.decrypted(keypair: state.keypair) ?? NSLocalizedString("New encrypted direct message", comment: "Notification that the user has received a new direct message")
        return LocalNotification(type: .dm, event: ev, target: .note(ev), content: convo)
    }
    else if type == .zap,
            state.settings.zap_notification {
        return LocalNotification(type: .zap, event: ev, target: .note(ev), content: ev.content)
    }
    
    return nil
}

func create_local_notification(profiles: Profiles, notify: LocalNotification) {
    let displayName = event_author_name(profiles: profiles, pubkey: notify.event.pubkey)
    
    guard let (content, identifier) = NotificationFormatter.shared.format_message(displayName: displayName, notify: notify) else { return }

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

func render_notification_content_preview(ndb: Ndb, ev: NostrEvent, profiles: Profiles, keypair: Keypair) -> String {

    let prefix_len = 300
    let artifacts = render_note_content(ndb: ndb, ev: ev, profiles: profiles, keypair: keypair)

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
    let profile_txn = profiles.lookup(id: pubkey)
    let profile = profile_txn?.unsafeUnownedValue
    return Profile.displayName(profile: profile, pubkey: pubkey).username.truncate(maxLength: 50)
}

@MainActor
func get_zap(from ev: NostrEvent, state: HeadlessDamusState) async -> Zap? {
    return await withCheckedContinuation { continuation in
        process_zap_event(state: state, ev: ev) { zapres in
            continuation.resume(returning: zapres.get_zap())
        }
    }
}

@MainActor
func process_zap_event(state: HeadlessDamusState, ev: NostrEvent, completion: @escaping (ProcessZapResult) -> Void) {
    // These are zap notifications
    guard let ptag = get_zap_target_pubkey(ev: ev, ndb: state.ndb) else {
        completion(.failed)
        return
    }

    // just return the zap if we already have it
    if let zap = state.zaps.zaps[ev.id], case .zap(let z) = zap {
        completion(.already_processed(z))
        return
    }
    
    if let local_zapper = state.profiles.lookup_zapper(pubkey: ptag) {
        guard let zap = process_zap_event_with_zapper(state: state, ev: ev, zapper: local_zapper) else {
            completion(.failed)
            return
        }
        state.add_zap(zap: .zap(zap))
        completion(.done(zap))
        return
    }
    
    guard let txn = state.profiles.lookup_with_timestamp(ptag),
          let lnurl = txn.map({ pr in pr?.lnurl }).value else {
        completion(.failed)
        return
    }

    Task { [lnurl] in
        guard let zapper = await fetch_zapper_from_lnurl(lnurls: state.lnurls, pubkey: ptag, lnurl: lnurl) else {
            completion(.failed)
            return
        }
        
        DispatchQueue.main.async {
            state.profiles.profile_data(ptag).zapper = zapper
            guard let zap = process_zap_event_with_zapper(state: state, ev: ev, zapper: zapper) else {
                completion(.failed)
                return
            }
            state.add_zap(zap: .zap(zap))
            completion(.done(zap))
        }
    }
}

// securely get the zap target's pubkey. this can be faked so we need to be
// careful
func get_zap_target_pubkey(ev: NostrEvent, ndb: Ndb) -> Pubkey? {
    let etags = Array(ev.referenced_ids)

    guard let etag = etags.first else {
        // no etags, ptag-only case

        guard let a = ev.referenced_pubkeys.just_one() else {
            return nil
        }

        // TODO: just return data here
        return a
    }

    // we have an e-tag

    // ensure that there is only 1 etag to stop fake note zap attacks
    guard etags.count == 1 else {
        return nil
    }

    // we can't trust the p tag on note zaps because they can be faked
    guard let txn = ndb.lookup_note(etag),
          let pk = txn.unsafeUnownedValue?.pubkey else {
        // We don't have the event in cache so we can't check the pubkey.

        // We could return this as an invalid zap but that wouldn't be correct
        // all of the time, and may reject valid zaps. What we need is a new
        // unvalidated zap state, but for now we simply leak a bit of correctness...

        return ev.referenced_pubkeys.just_one()
    }

    return pk
}

fileprivate func process_zap_event_with_zapper(state: HeadlessDamusState, ev: NostrEvent, zapper: Pubkey) -> Zap? {
    let our_keypair = state.keypair
    
    guard let zap = Zap.from_zap_event(zap_ev: ev, zapper: zapper, our_privkey: our_keypair.privkey) else {
        return nil
    }
    
    state.add_zap(zap: .zap(zap))
    
    return zap
}

enum ProcessZapResult {
    case already_processed(Zap)
    case done(Zap)
    case failed
    
    func get_zap() -> Zap? {
        switch self {
            case .already_processed(let zap):
                return zap
            case .done(let zap):
                return zap
            default:
                return nil
        }
    }
}
