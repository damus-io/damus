//
//  Mute.swift
//  damus
//
//  Created by William Casarin on 2023-01-25.
//

import Foundation

func create_or_update_mutelist(keypair: FullKeypair, mprev: NostrEvent?, to_add: String) -> NostrEvent? {
    return create_or_update_list_event(keypair: keypair, mprev: mprev, to_add: to_add, list_name: "mute", list_type: "p")
}

func remove_from_mutelist(keypair: FullKeypair, prev: NostrEvent, to_remove: String) -> NostrEvent? {
    return remove_from_list_event(keypair: keypair, prev: prev, to_remove: to_remove, tag_type: "p")
}

func create_or_update_list_event(keypair: FullKeypair, mprev: NostrEvent?, to_add: String, list_name: String, list_type: String) -> NostrEvent? {
    let pubkey = keypair.pubkey
    
    if let prev = mprev {
        if let okprev = ensure_list_name(list: prev, name: list_name), prev.pubkey == keypair.pubkey {
            return add_to_list_event(keypair: keypair, prev: okprev, to_add: to_add, tag_type: list_type)
        }
    }
    
    let tags = [["d", list_name], [list_type, to_add]]
    let ev = NostrEvent(content: "", pubkey: pubkey, kind: 30000, tags: tags)
    
    ev.tags = tags
    ev.id = calculate_event_id(ev: ev)
    ev.sig = sign_event(privkey: keypair.privkey, ev: ev)
    
    return ev
}

func remove_from_list_event(keypair: FullKeypair, prev: NostrEvent, to_remove: String, tag_type: String) -> NostrEvent? {
    var exists = false
    for tag in prev.tags {
        if tag.count >= 2 && tag[0] == tag_type && tag[1] == to_remove {
            exists = true
        }
    }
    
    // make sure we actually have the pubkey to remove
    guard exists else {
        return nil
    }
    
    let new_tags = prev.tags.filter { tag in
        !(tag.count >= 2 && tag[0] == tag_type && tag[1] == to_remove)
    }
        
    let ev = NostrEvent(content: prev.content, pubkey: keypair.pubkey, kind: 30000, tags: new_tags)
    ev.id = calculate_event_id(ev: ev)
    ev.sig = sign_event(privkey: keypair.privkey, ev: ev)
    
    return ev
}

func add_to_list_event(keypair: FullKeypair, prev: NostrEvent, to_add: String, tag_type: String) -> NostrEvent? {
    for tag in prev.tags {
        // we are already muting this user
        if tag.count >= 2 && tag[0] == tag_type && tag[1] == to_add {
            return nil
        }
    }
    
    let new = NostrEvent(content: prev.content, pubkey: keypair.pubkey, kind: 30000, tags: prev.tags)
    new.tags.append([tag_type, to_add])
    new.id = calculate_event_id(ev: new)
    new.sig = sign_event(privkey: keypair.privkey, ev: new)
    
    return new
}

func ensure_list_name(list: NostrEvent, name: String) -> NostrEvent? {
    for tag in list.tags {
        if tag.count >= 2 && tag[0] == "d" {
            if tag[1] != name {
                return nil
            } else {
                return list
            }
        }
    }
    
    list.tags.insert(["d", name], at: 0)
    
    return list
}
