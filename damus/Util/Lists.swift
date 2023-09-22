//
//  Mute.swift
//  damus
//
//  Created by William Casarin on 2023-01-25.
//

import Foundation

func create_or_update_mutelist(keypair: FullKeypair, mprev: NostrEvent?, to_add: RefId) -> NostrEvent? {
    return create_or_update_list_event(keypair: keypair, mprev: mprev, to_add: to_add, list_name: "mute", list_type: "p")
}

func remove_from_mutelist(keypair: FullKeypair, prev: NostrEvent, to_remove: RefId) -> NostrEvent? {
    return remove_from_list_event(keypair: keypair, prev: prev, to_remove: to_remove)
}

func create_or_update_list_event(keypair: FullKeypair, mprev: NostrEvent?, to_add: RefId, list_name: String, list_type: String) -> NostrEvent? {
    if let prev = mprev,
       prev.pubkey == keypair.pubkey,
       matches_list_name(tags: prev.tags, name: list_name)
    {
        return add_to_list_event(keypair: keypair, prev: prev, to_add: to_add)
    }
    
    let tags = [["d", list_name], [list_type, to_add.description]]
    return NostrEvent(content: "", keypair: keypair.to_keypair(), kind: 30000, tags: tags)
}

func remove_from_list_event(keypair: FullKeypair, prev: NostrEvent, to_remove: RefId) -> NostrEvent? {
    var removed = false

    let tags = prev.tags.reduce(into: [[String]](), { acc, tag in
        if let ref_id = RefId.from_tag(tag: tag), ref_id == to_remove {
            removed = true
            return
        }
        acc.append(tag.strings())
    })

    guard removed else {
        return nil
    }

    return NostrEvent(content: prev.content, keypair: keypair.to_keypair(), kind: 30000, tags: tags)
}

func add_to_list_event(keypair: FullKeypair, prev: NostrEvent, to_add: RefId) -> NostrEvent? {
    for tag in prev.tags {
        // we are already muting this user
        if let ref = RefId.from_tag(tag: tag), to_add == ref {
            return nil
        }
    }

    var tags = prev.tags.strings()
    tags.append(to_add.tag)

    return NostrEvent(content: prev.content, keypair: keypair.to_keypair(), kind: 30000, tags: tags)
}

func matches_list_name(tags: Tags, name: String) -> Bool {
    for tag in tags {
        if tag.count >= 2 && tag[0].matches_char("d") {
            return tag[1].matches_str(name)
        }
    }

    return false
}
