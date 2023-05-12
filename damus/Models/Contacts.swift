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
                new_mutes.append(d)
            } else {
                new_unmutes.append(d)
            }
        }
        
        // TODO: set local mutelist here
        self.muted = Set(ev.referenced_pubkeys.map({ $0.ref_id }))
        
        if new_mutes.count > 0 {
            notify(.new_mutes, new_mutes)
        }
        
        if new_unmutes.count > 0 {
            notify(.new_unmutes, new_unmutes)
        }
    }
    
    func remove_friend(_ pubkey: String) {
        friends.remove(pubkey)
    }
    
    func get_friend_list() -> [String] {
        return Array(friends)
    }
    
    func add_friend_pubkey(_ pubkey: String) {
        friends.insert(pubkey)
    }
    
    func add_friend_contact(_ contact: NostrEvent) {
        friends.insert(contact.pubkey)
        for tag in contact.tags {
            if tag.count >= 2 && tag[0] == "p" {
                friend_of_friends.insert(tag[1])
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
}

func follow_user(pool: RelayPool, our_contacts: NostrEvent?, pubkey: String, privkey: String, follow: ReferencedId) -> NostrEvent? {
    guard let ev = follow_user_event(our_contacts: our_contacts, our_pubkey: pubkey, follow: follow) else {
        return nil
    }
    
    ev.calculate_id()
    ev.sign(privkey: privkey)
    
    
    pool.send(.event(ev))
    
    return ev
}

func unfollow_user(postbox: PostBox, our_contacts: NostrEvent?, pubkey: String, privkey: String, unfollow: String) -> NostrEvent? {
    guard let cs = our_contacts else {
        return nil
    }
    
    let ev = unfollow_user_event(our_contacts: cs, our_pubkey: pubkey, unfollow: unfollow)
    ev.calculate_id()
    ev.sign(privkey: privkey)
    
    postbox.send(ev)
    
    return ev
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


func decode_json_relays(_ content: String) -> [String: RelayInfo]? {
    return decode_json(content)
}

func remove_relay(ev: NostrEvent, current_relays: [RelayDescriptor], privkey: String, relay: String) -> NostrEvent? {
    var relays = ensure_relay_info(relays: current_relays, content: ev.content)
    
    relays.removeValue(forKey: relay)
    
    print("remove_relay \(relays)")
    guard let content = encode_json(relays) else {
        return nil
    }
    
    let new_ev = NostrEvent(content: content, pubkey: ev.pubkey, kind: 3, tags: ev.tags)
    new_ev.calculate_id()
    new_ev.sign(privkey: privkey)
    return new_ev
}

func add_relay(ev: NostrEvent, privkey: String, current_relays: [RelayDescriptor], relay: String, info: RelayInfo) -> NostrEvent? {
    var relays = ensure_relay_info(relays: current_relays, content: ev.content)
    
    guard relays.index(forKey: relay) == nil else {
        return nil
    }
    
    relays[relay] = info
    
    guard let content = encode_json(relays) else {
        return nil
    }
    
    let new_ev = NostrEvent(content: content, pubkey: ev.pubkey, kind: 3, tags: ev.tags)
    new_ev.calculate_id()
    new_ev.sign(privkey: privkey)
    return new_ev
}

func ensure_relay_info(relays: [RelayDescriptor], content: String) -> [String: RelayInfo] {
    guard let relay_info = decode_json_relays(content) else {
        return make_contact_relays(relays)
    }
    return relay_info
}

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
        acc[relay.url.url.absoluteString] = relay.info
    }
}
