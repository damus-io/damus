//
//  Contacts+.swift
//  damus
//
//  Extra functionality and utilities for `Contacts.swift`
//
//  Created by Daniel D’Aquino on 2023-11-24.
//

import Foundation

func follow_reference(box: PostBox, our_contacts: NostrEvent?, keypair: FullKeypair, follow: FollowRef) -> NostrEvent? {
    guard let ev = follow_user_event(our_contacts: our_contacts, keypair: keypair, follow: follow) else {
        return nil
    }
    
    box.send(ev)

    return ev
}

func unfollow_reference(postbox: PostBox, our_contacts: NostrEvent?, keypair: FullKeypair, unfollow: FollowRef) -> NostrEvent? {
    guard let cs = our_contacts else {
        return nil
    }
    
    guard let ev = unfollow_reference_event(our_contacts: cs, keypair: keypair, unfollow: unfollow) else {
        return nil
    }

    postbox.send(ev)
    
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


func decode_json_relays(_ content: String) -> [String: RelayInfo]? {
    return decode_json(content)
}

func decode_json_relays(_ content: String) -> [RelayURL: RelayInfo]? {
    return decode_json(content)
}

func remove_relay(ev: NostrEvent, current_relays: [RelayDescriptor], keypair: FullKeypair, relay: RelayURL) -> NostrEvent?{
    var relays = ensure_relay_info(relays: current_relays, content: ev.content)
    
    relays.removeValue(forKey: relay)
    
    guard let content = encode_json(relays) else {
        return nil
    }
    
    return NostrEvent(content: content, keypair: keypair.to_keypair(), kind: 3, tags: ev.tags.strings())
}

func add_relay(ev: NostrEvent, keypair: FullKeypair, current_relays: [RelayDescriptor], relay: RelayURL, info: RelayInfo) -> NostrEvent? {
    var relays = ensure_relay_info(relays: current_relays, content: ev.content)
    
    
    guard relays.index(forKey: relay) == nil else {
        return nil
    }
    
    relays[relay] = info
    
    guard let content = encode_json(relays) else {
        return nil
    }
    
    return NostrEvent(content: content, keypair: keypair.to_keypair(), kind: 3, tags: ev.tags.strings())
}

func ensure_relay_info(relays: [RelayDescriptor], content: String) -> [RelayURL: RelayInfo] {
    return decode_json_relays(content) ?? make_contact_relays(relays)
}

func is_already_following(contacts: NostrEvent, follow: FollowRef) -> Bool {
    return contacts.references.contains { ref in
        switch (ref, follow) {
        case let (.hashtag(ht), .hashtag(follow_ht)):
            return ht.string() == follow_ht
        case let (.pubkey(pk), .pubkey(follow_pk)):
            return pk == follow_pk
        case (.hashtag, .pubkey), (.pubkey, .hashtag),
             (.event, _), (.quote, _), (.param, _):
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

func make_contact_relays(_ relays: [RelayDescriptor]) -> [RelayURL: RelayInfo] {
    return relays.reduce(into: [:]) { acc, relay in
        acc[relay.url] = relay.info
    }
}

