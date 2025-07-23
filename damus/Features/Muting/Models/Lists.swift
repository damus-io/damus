//
//  Mute.swift
//  damus
//
//  Created by William Casarin on 2023-01-25.
//

import Foundation

func create_or_update_mutelist(keypair: FullKeypair, mprev: NostrEvent?, to_add: Set<MuteItem>) -> NostrEvent? {
    let muted_items: Set<MuteItem> = (mprev?.mute_list ?? Set<MuteItem>()).union(to_add).filter { !$0.is_expired() }
    let tags: [[String]] = muted_items.map { $0.tag }
    return NostrEvent(content: mprev?.content ?? "", keypair: keypair.to_keypair(), kind: NostrKind.mute_list.rawValue, tags: tags)
}

func create_or_update_mutelist(keypair: FullKeypair, mprev: NostrEvent?, to_add: MuteItem) -> NostrEvent? {
    return create_or_update_mutelist(keypair: keypair, mprev: mprev, to_add: [to_add])
}

func remove_from_mutelist(keypair: FullKeypair, prev: NostrEvent?, to_remove: MuteItem) -> NostrEvent? {
    let muted_items: Set<MuteItem> = (prev?.mute_list ?? Set<MuteItem>()).subtracting([to_remove]).filter { !$0.is_expired() }
    let tags: [[String]] = muted_items.map { $0.tag }
    return NostrEvent(content: "", keypair: keypair.to_keypair(), kind: NostrKind.mute_list.rawValue, tags: tags)
}

func toggle_from_mutelist(keypair: FullKeypair, prev: NostrEvent?, to_toggle: MuteItem) -> NostrEvent? {
    let existing_muted_items: Set<MuteItem> = (prev?.mute_list ?? Set<MuteItem>())

    if existing_muted_items.contains(to_toggle) {
        // Already exists, remove
        return remove_from_mutelist(keypair: keypair, prev: prev, to_remove: to_toggle)
    } else {
        // Doesn't exist, add
        return create_or_update_mutelist(keypair: keypair, mprev: prev, to_add: to_toggle)
    }
}
