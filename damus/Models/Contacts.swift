//
//  Contacts.swift
//  damus
//
//  Created by William Casarin on 2022-05-14.
//

import Foundation


class Contacts {
    var friends: Set<String> = Set()
    var event: NostrEvent?
    
    func is_friend(_ pubkey: String) -> Bool {
        return friends.contains(pubkey)
    }
    
    func follow_state(_ pubkey: String) -> FollowState {
        return is_friend(pubkey) ? .follows : .unfollows
    }
}


func create_contacts(relays: [RelayDescriptor], our_pubkey: String, follow: ReferencedId) -> NostrEvent {
    let kind = NostrKind.contacts.rawValue
    let content = create_contacts_content(relays) ?? "{}"
    let tags = [refid_to_tag(follow)]
    return NostrEvent(content: content, pubkey: our_pubkey, kind: kind, tags: tags)
}

func create_contacts_content(_ relays: [RelayDescriptor]) -> String? {
    // TODO: just create a new one of this is corrupted?
    let crelays = make_contact_relays(relays)
    guard let encoded = encode_json(crelays) else {
        return nil
    }
    return encoded
}


func follow_user(pool: RelayPool, our_contacts: NostrEvent?, pubkey: String, privkey: String, follow: ReferencedId) -> Bool {
    guard let ev = follow_user_event(our_contacts: our_contacts, our_pubkey: pubkey, follow: follow) else {
        return false
    }
    
    ev.calculate_id()
    ev.sign(privkey: privkey)
    
    pool.send(.event(ev))
    
    return true
}

func unfollow_user(pool: RelayPool, our_contacts: NostrEvent?, pubkey: String, privkey: String, unfollow: String) -> Bool {
    guard let cs = our_contacts else {
        return false
    }
    
    let ev = unfollow_user_event(our_contacts: cs, our_pubkey: pubkey, unfollow: unfollow)
    ev.calculate_id()
    ev.sign(privkey: privkey)
    
    pool.send(.event(ev))
    
    return true
}

func unfollow_user_event(our_contacts: NostrEvent, our_pubkey: String, unfollow: String) -> NostrEvent {
    let tags = our_contacts.tags.filter { tag in
        if tag.count >= 2 && tag[0] == "p" && tag[1] == unfollow {
            return false
        }
        return true
    }
    
    let kind = NostrKind.contacts.rawValue
    return NostrEvent(content: our_contacts.content, pubkey: our_pubkey, kind: kind, tags: tags)
}

func follow_user_event(our_contacts: NostrEvent?, our_pubkey: String, follow: ReferencedId) -> NostrEvent? {
    guard let cs = our_contacts else {
        // don't create contacts for now so we don't nuke our contact list due to connectivity issues
        // we should only create contacts during profile creation
        //return create_contacts(relays: relays, our_pubkey: our_pubkey, follow: follow)
        return nil
    }

    guard let ev = follow_with_existing_contacts(our_pubkey: our_pubkey, our_contacts: cs, follow: follow) else {
        return nil
    }
    
    return ev
}

/*
func ensure_relay_info(relays: [RelayDescriptor], content: String) -> [String: RelayInfo] {
    guard let relay_info = decode_json_relays(content) else {
        return make_contact_relays(relays)
    }
    return relay_info
}
 */

func follow_with_existing_contacts(our_pubkey: String, our_contacts: NostrEvent, follow: ReferencedId) -> NostrEvent? {
    // don't update if we're already following
    if our_contacts.references(id: follow.ref_id, key: "p") {
        return nil
    }
    
    let kind = NostrKind.contacts.rawValue
    var tags = our_contacts.tags
    tags.append(refid_to_tag(follow))
    return NostrEvent(content: our_contacts.content, pubkey: our_pubkey, kind: kind, tags: tags)
}

func make_contact_relays(_ relays: [RelayDescriptor]) -> [String: RelayInfo] {
    return relays.reduce(into: [:]) { acc, relay in
        acc[relay.url.absoluteString] = relay.info
    }
}


func is_friend_event(_ ev: NostrEvent, our_pubkey: String, friends: Set<String>) -> Bool
{
    if ev.pubkey == our_pubkey {
        return true
    }
    
    if friends.contains(ev.pubkey) {
        return true
    }
    
    if ev.is_reply {
        // show our replies?
        if ev.pubkey == our_pubkey {
            return true
        }
        for pk in ev.referenced_pubkeys {
            if friends.contains(pk.ref_id) {
                return true
            }
        }
    }
    
    return false
}
