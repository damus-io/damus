//
//  Contacts.swift
//  damus
//
//  Created by William Casarin on 2022-05-14.
//

import Foundation


class Contacts {
    private var friends: Set<String> = Set()
    private var friend_of_friends: Set<String> = Set()
    /// Tracks which friends are friends of a given pubkey.
    private var pubkey_to_our_friends = [String : Set<String>]()
    private var muted: Set<String> = Set()
    
    let our_pubkey: String
    var event: NostrEvent?
    var mutelist: NostrEvent?
    
    init(our_pubkey: String) {
        self.our_pubkey = our_pubkey
    }
    
    func is_muted(_ pk: String) -> Bool {
        return muted.contains(pk)
    }
    
    func set_mutelist(_ ev: NostrEvent) {
        let oldlist = self.mutelist
        self.mutelist = ev
        
        let old = Set(oldlist?.referenced_pubkeys.map({ $0.ref_id }) ?? [])
        let new = Set(ev.referenced_pubkeys.map({ $0.ref_id }))
        let diff = old.symmetricDifference(new)
        
        var new_mutes = Array<String>()
        var new_unmutes = Array<String>()
        
        for d in diff {
            if new.contains(d) {
                new_mutes.append(d.string())
            } else {
                new_unmutes.append(d.string())
            }
        }

        // TODO: set local mutelist here
        self.muted = Set(ev.referenced_pubkeys.map({ $0.ref_id.string() }))

        if new_mutes.count > 0 {
            notify(.new_mutes, new_mutes)
        }
        
        if new_unmutes.count > 0 {
            notify(.new_unmutes, new_unmutes)
        }
    }
    
    func remove_friend(_ pubkey: String) {
        friends.remove(pubkey)

        pubkey_to_our_friends.forEach {
            pubkey_to_our_friends[$0.key]?.remove(pubkey)
        }
    }
    
    func get_friend_list() -> Set<String> {
        return friends
    }

    func get_followed_hashtags() -> Set<String> {
        guard let ev = self.event else { return Set() }
        return Set(ev.referenced_hashtags.map({ $0.ref_id.string() }))
    }

    func add_friend_pubkey(_ pubkey: String) {
        friends.insert(pubkey)
    }
    
    func add_friend_contact(_ contact: NostrEvent) {
        friends.insert(contact.pubkey)
        for tag in contact.referenced_pubkeys {
            let pk = tag.id.string()
            friend_of_friends.insert(pk)

            // Exclude themself and us.
            if contact.pubkey != our_pubkey && contact.pubkey != pk {
                if pubkey_to_our_friends[pk] == nil {
                    pubkey_to_our_friends[pk] = Set<String>()
                }

                pubkey_to_our_friends[pk]?.insert(contact.pubkey)
            }
        }
    }
    
    func is_friend_of_friend(_ pubkey: String) -> Bool {
        return friend_of_friends.contains(pubkey)
    }
    
    func is_in_friendosphere(_ pubkey: String) -> Bool {
        return friends.contains(pubkey) || friend_of_friends.contains(pubkey)
    }

    func is_friend(_ pubkey: String) -> Bool {
        return friends.contains(pubkey)
    }
    
    func is_friend_or_self(_ pubkey: String) -> Bool {
        return pubkey == our_pubkey || is_friend(pubkey)
    }
    
    func follow_state(_ pubkey: String) -> FollowState {
        return is_friend(pubkey) ? .follows : .unfollows
    }

    /// Gets the list of pubkeys of our friends who follow the given pubkey.
    func get_friended_followers(_ pubkey: String) -> [String] {
        return Array((pubkey_to_our_friends[pubkey] ?? Set()))
    }
}

func follow_reference(box: PostBox, our_contacts: NostrEvent?, keypair: FullKeypair, follow: ReferencedId) -> NostrEvent? {
    guard let ev = follow_user_event(our_contacts: our_contacts, keypair: keypair, follow: follow) else {
        return nil
    }
    
    box.send(ev)

    return ev
}

func unfollow_reference(postbox: PostBox, our_contacts: NostrEvent?, keypair: FullKeypair, unfollow: ReferencedId) -> NostrEvent? {
    guard let cs = our_contacts else {
        return nil
    }
    
    guard let ev = unfollow_reference_event(our_contacts: cs, keypair: keypair, unfollow: unfollow) else {
        return nil
    }

    postbox.send(ev)
    
    return ev
}

func unfollow_reference_event(our_contacts: NostrEvent, keypair: FullKeypair, unfollow: ReferencedId) -> NostrEvent? {
    let tags = our_contacts.tags.reduce(into: [[String]]()) { ts, tag in
        if tag.count >= 2,
           let fst = unfollow.key.first,
           let afst = AsciiCharacter(fst),
           tag[0].matches_char(afst),
           tag[1].matches_str(unfollow.ref_id)
        {
            return
        }

        ts.append(tag.strings())
    }

    let kind = NostrKind.contacts.rawValue

    return NostrEvent(content: our_contacts.content, keypair: keypair.to_keypair(), kind: kind, tags: Array(tags))
}

func follow_user_event(our_contacts: NostrEvent?, keypair: FullKeypair, follow: ReferencedId) -> NostrEvent? {
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

func remove_relay(ev: NostrEvent, current_relays: [RelayDescriptor], keypair: FullKeypair, relay: String) -> NostrEvent?{
    var relays = ensure_relay_info(relays: current_relays, content: ev.content)
    relays.removeValue(forKey: relay)
    
    guard let content = encode_json(relays) else {
        return nil
    }
    
    return NostrEvent(content: content, keypair: keypair.to_keypair(), kind: 3, tags: ev.tags.strings())
}

func add_relay(ev: NostrEvent, keypair: FullKeypair, current_relays: [RelayDescriptor], relay: String, info: RelayInfo) -> NostrEvent? {
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

func ensure_relay_info(relays: [RelayDescriptor], content: String) -> [String: RelayInfo] {
    guard let relay_info = decode_json_relays(content) else {
        return make_contact_relays(relays)
    }
    return relay_info
}

func is_already_following(contacts: NostrEvent, follow: ReferencedId) -> Bool {
    guard let key = follow.key.first_char() else { return false }
    return contacts.references(id: follow.ref_id, key: key)
}

func follow_with_existing_contacts(keypair: FullKeypair, our_contacts: NostrEvent, follow: ReferencedId) -> NostrEvent? {
    // don't update if we're already following
    if is_already_following(contacts: our_contacts, follow: follow) {
        return nil
    }

    let kind = NostrKind.contacts.rawValue

    var tags = our_contacts.tags.strings()
    tags.append(refid_to_tag(follow))

    return NostrEvent(content: our_contacts.content, keypair: keypair.to_keypair(), kind: kind, tags: tags)
}

func make_contact_relays(_ relays: [RelayDescriptor]) -> [String: RelayInfo] {
    return relays.reduce(into: [:]) { acc, relay in
        acc[relay.url.url.absoluteString] = relay.info
    }
}
