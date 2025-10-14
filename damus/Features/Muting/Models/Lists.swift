//
//  Mute.swift
//  damus
//
//  Created by William Casarin on 2023-01-25.
//

import Foundation

/// Creates or updates a mutelist by adding items.
/// Replaces existing items with same identity to update expiration.
func create_or_update_mutelist(keypair: FullKeypair, mprev: NostrEvent?, to_add: Set<MuteItem>) -> NostrEvent? {
    var merged: [MuteItem] = Array(mprev?.mute_list ?? [])

    for item in to_add {
        if let index = merged.firstIndex(where: { $0.matchesStorage(item) }) {
            // Replace to update expiration
            merged[index] = item
        } else {
            merged.append(item)
        }
    }

    let tags: [[String]] = merged.map { $0.tag }
    return NostrEvent(content: mprev?.content ?? "", keypair: keypair.to_keypair(), kind: NostrKind.mute_list.rawValue, tags: tags)
}

/// Creates or updates a mutelist by adding a single item.
func create_or_update_mutelist(keypair: FullKeypair, mprev: NostrEvent?, to_add: MuteItem) -> NostrEvent? {
    return create_or_update_mutelist(keypair: keypair, mprev: mprev, to_add: [to_add])
}

/// Removes an item from the mutelist.
/// Uses `matchesStorage` to find and remove items, including expired ones.
func remove_from_mutelist(keypair: FullKeypair, prev: NostrEvent?, to_remove: MuteItem) -> NostrEvent? {
    let existing: [MuteItem] = Array(prev?.mute_list ?? [])
    let filtered = existing.filter { !$0.matchesStorage(to_remove) }
    let tags: [[String]] = filtered.map { $0.tag }
    return NostrEvent(content: "", keypair: keypair.to_keypair(), kind: NostrKind.mute_list.rawValue, tags: tags)
}

/// Toggles an item in the mutelist (adds if not present, removes if present).
/// Uses `matchesStorage` to check existence, allowing toggle of expired items.
func toggle_from_mutelist(keypair: FullKeypair, prev: NostrEvent?, to_toggle: MuteItem) -> NostrEvent? {
    let existing: [MuteItem] = Array(prev?.mute_list ?? [])

    if existing.contains(where: { $0.matchesStorage(to_toggle) }) {
        // Already exists, remove
        return remove_from_mutelist(keypair: keypair, prev: prev, to_remove: to_toggle)
    } else {
        // Doesn't exist, add
        return create_or_update_mutelist(keypair: keypair, mprev: prev, to_add: to_toggle)
    }
}
