//
//  Contacts+.swift
//  damus
//
//  Extra functionality and utilities for `Contacts.swift`
//
//  Created by Daniel D’Aquino on 2023-11-24.
//

import Foundation

func follow_reference(box: PostBox, our_contacts: NostrEvent?, keypair: FullKeypair, follow: FollowRef) async -> NostrEvent? {
    guard let ev = follow_user_event(our_contacts: our_contacts, keypair: keypair, follow: follow) else {
        return nil
    }
    
    await box.send(ev)

    return ev
}

func unfollow_reference(postbox: PostBox, our_contacts: NostrEvent?, keypair: FullKeypair, unfollow: FollowRef) async -> NostrEvent? {
    guard let cs = our_contacts else {
        return nil
    }
    
    guard let ev = unfollow_reference_event(our_contacts: cs, keypair: keypair, unfollow: unfollow) else {
        return nil
    }

    await postbox.send(ev)
    
    return ev
}

func unfollow_reference_event(our_contacts: NostrEvent, keypair: FullKeypair, unfollow: FollowRef) -> NostrEvent? {
    let tags = our_contacts.tags.reduce(into: [[String]]()) { ts, tag in
        if let tag = FollowRef.from_tag(tag: tag), tag == unfollow {
            return
        }

        ts.append(tag.strings())
    }

    let kind = NostrKind.contacts.rawValue

    return NostrEvent(content: our_contacts.content, keypair: keypair.to_keypair(), kind: kind, tags: Array(tags))
}

func follow_user_event(our_contacts: NostrEvent?, keypair: FullKeypair, follow: FollowRef) -> NostrEvent? {
    guard let cs = our_contacts else {
        // don't create contacts for now so we don't nuke our contact list due to connectivity issues
        // we should only create contacts during profile creation
        //return create_contacts(relays: relays, our_pubkey: our_pubkey, follow: follow)
        return nil
    }

    guard let ev = follow_with_existing_contacts(keypair: keypair, our_contacts: cs, follow: follow) else {
        return nil
    }
    
    return ev
}


func decode_json_relays(_ content: String) -> [RelayURL: LegacyKind3RelayRWConfiguration]? {
    return decode_json(content)
}

func is_already_following(contacts: NostrEvent, follow: FollowRef) -> Bool {
    return contacts.references.contains { ref in
        switch (ref, follow) {
        case let (.hashtag(ht), .hashtag(follow_ht)):
            return ht.hashtag == follow_ht
        case let (.pubkey(pk), .pubkey(follow_pk)):
            return pk == follow_pk
        case (.hashtag, .pubkey), (.pubkey, .hashtag),
            (.event, _), (.quote, _), (.param, _), (.naddr, _), (.reference(_), _):
            return false
        }
    }
}
func follow_with_existing_contacts(keypair: FullKeypair, our_contacts: NostrEvent, follow: FollowRef) -> NostrEvent? {
    // don't update if we're already following
    if is_already_following(contacts: our_contacts, follow: follow) {
        return nil
    }

    let kind = NostrKind.contacts.rawValue

    var tags = our_contacts.tags.strings()
    tags.append(follow.tag)

    return NostrEvent(content: our_contacts.content, keypair: keypair.to_keypair(), kind: kind, tags: tags)
}

/// Creates a single contacts event that adds multiple follows at once.
/// This avoids race conditions when following many users simultaneously (e.g., "Follow All").
/// - Parameters:
///   - box: The PostBox to send the event through.
///   - our_contacts: The current contacts event, or nil if none exists.
///   - keypair: The user's full keypair for signing.
///   - follows: The list of follow references to add.
/// - Returns: The new contacts event if successful, nil otherwise.
func follow_multiple_references(box: PostBox, our_contacts: NostrEvent?, keypair: FullKeypair, follows: [FollowRef]) async -> NostrEvent? {
    guard let ev = follow_multiple_users_event(our_contacts: our_contacts, keypair: keypair, follows: follows) else {
        return nil
    }

    await box.send(ev)
    return ev
}

/// Creates a contacts event that adds multiple follows at once.
/// - Parameters:
///   - our_contacts: The current contacts event, or nil if none exists.
///   - keypair: The user's full keypair for signing.
///   - follows: The list of follow references to add.
/// - Returns: The new contacts event, or nil if there's nothing to add or no existing contacts.
func follow_multiple_users_event(our_contacts: NostrEvent?, keypair: FullKeypair, follows: [FollowRef]) -> NostrEvent? {
    guard let cs = our_contacts else {
        // don't create contacts for now so we don't nuke our contact list due to connectivity issues
        // we should only create contacts during profile creation
        return nil
    }

    let kind = NostrKind.contacts.rawValue
    var tags = cs.tags.strings()
    var addedAny = false

    for follow in follows {
        // Skip if already following
        if is_already_following(contacts: cs, follow: follow) {
            continue
        }

        // Skip if already added in this batch
        let newTag = follow.tag
        if tags.contains(where: { $0 == newTag }) {
            continue
        }

        tags.append(newTag)
        addedAny = true
    }

    // Return nil if nothing was added
    guard addedAny else { return nil }

    return NostrEvent(content: cs.content, keypair: keypair.to_keypair(), kind: kind, tags: tags)
}

