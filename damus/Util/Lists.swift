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
    if let prev = mprev,
       prev.pubkey == keypair.pubkey,
       matches_list_name(tags: prev.tags, name: list_name)
    {
        return add_to_list_event(keypair: keypair, prev: prev, to_add: to_add, tag_type: list_type)
    }
    
    let tags = [["d", list_name], [list_type, to_add]]
    return NostrEvent(content: "", keypair: keypair.to_keypair(), kind: 30000, tags: tags)
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
        
    return NostrEvent(content: prev.content, keypair: keypair.to_keypair(), kind: 30000, tags: new_tags)
}

func add_to_list_event(keypair: FullKeypair, prev: NostrEvent, to_add: String, tag_type: String) -> NostrEvent? {
    for tag in prev.tags {
        // we are already muting this user
        if tag.count >= 2 && tag[0] == tag_type && tag[1] == to_add {
            return nil
        }
    }

    var tags = Array(prev.tags)
    tags.append([tag_type, to_add])

    return NostrEvent(content: prev.content, keypair: keypair.to_keypair(), kind: 30000, tags: tags)
}

func matches_list_name(tags: [[String]], name: String) -> Bool {
    for tag in tags {
        if tag.count >= 2 && tag[0] == "d" {
            return tag[1] == name
        }
    }

    return false
}
