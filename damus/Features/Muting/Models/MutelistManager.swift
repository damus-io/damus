//
//  MutelistManager.swift
//  damus
//
//  Created by Charlie Fish on 1/28/24.
//

import Foundation

@MainActor
class MutelistManager {
    let user_keypair: Keypair
    private(set) var event: NostrEvent? = nil

    var users: Set<MuteItem> = [] {
        didSet { self.reset_cache() }
    }
    var hashtags: Set<MuteItem> = [] {
        didSet { self.reset_cache() }
    }
    var threads: Set<MuteItem> = [] {
        didSet { self.reset_cache() }
    }
    var words: Set<MuteItem> = [] {
        didSet { self.reset_cache() }
    }

    var muted_notes_cache: [NoteId: EventMuteStatus] = [:]

    nonisolated init(user_keypair: Keypair) {
        self.user_keypair = user_keypair
    }

    func refresh_sets() {
        guard let referenced_mute_items = event?.referenced_mute_items else { return }

        var new_users: Set<MuteItem> = []
        var new_hashtags: Set<MuteItem> = []
        var new_threads: Set<MuteItem> = []
        var new_words: Set<MuteItem> = []

        for mute_item in referenced_mute_items {
            switch mute_item {
            case .user:
                new_users.insert(mute_item)
            case .hashtag:
                new_hashtags.insert(mute_item)
            case .word:
                new_words.insert(mute_item)
            case .thread:
                new_threads.insert(mute_item)
            }
        }

        users = new_users
        hashtags = new_hashtags
        threads = new_threads
        words = new_words
    }
    
    func reset_cache() {
        self.muted_notes_cache = [:]
    }

    /// Checks if an item is muted AND currently active (not expired).
    func is_muted(_ item: MuteItem) -> Bool {
        let set: Set<MuteItem>
        switch item {
        case .user:
            set = users
        case .hashtag:
            set = hashtags
        case .word:
            set = words
        case .thread:
            set = threads
        }
        // Find matching item and check if it's active
        guard let stored = set.first(where: { $0 == item }) else { return false }
        return stored.isActive()
    }

    func is_event_muted(_ ev: NostrEvent) -> Bool {
        return self.event_muted_reason(ev) != nil
    }

    /// Updates the mutelist, detecting adds, removes, and expiration changes.
    func set_mutelist(_ ev: NostrEvent) {
        let oldlist = self.event
        self.event = ev

        let oldItems = Array(oldlist?.mute_list ?? [])
        let newItems = Array(ev.mute_list ?? [])

        // Build identity-based maps
        var oldMap: [MuteItem: MuteItem] = [:]
        for item in oldItems { oldMap[item] = item }
        var newMap: [MuteItem: MuteItem] = [:]
        for item in newItems { newMap[item] = item }

        var new_mutes = Set<MuteItem>()
        var new_unmutes = Set<MuteItem>()

        // Process adds and expiration updates
        for (identity, newItem) in newMap {
            if let oldItem = oldMap[identity] {
                // Identity exists - check if expiration changed
                if oldItem.expirationDate != newItem.expirationDate {
                    remove_mute_item(oldItem)
                    add_mute_item(newItem)
                }
            } else {
                // New item
                add_mute_item(newItem)
                new_mutes.insert(newItem)
            }
        }

        // Process removals
        for (identity, oldItem) in oldMap {
            if newMap[identity] == nil {
                remove_mute_item(oldItem)
                new_unmutes.insert(oldItem)
            }
        }

        if !new_mutes.isEmpty {
            notify(.new_mutes(new_mutes))
        }

        if !new_unmutes.isEmpty {
            notify(.new_unmutes(new_unmutes))
        }
    }

    private func add_mute_item(_ item: MuteItem) {
        switch item {
        case .user(_, _):
            guard !users.contains(item) else { return }
            users.insert(item)
        case .hashtag(_, _):
            guard !hashtags.contains(item) else { return }
            hashtags.insert(item)
        case .word(_, _):
            guard !words.contains(item) else { return }
            words.insert(item)
        case .thread(_, _):
            guard !threads.contains(item) else { return }
            threads.insert(item)
        }
    }

    private func remove_mute_item(_ item: MuteItem) {
        switch item {
        case .user(_, _):
            users.remove(item)
        case .hashtag(_, _):
            hashtags.remove(item)
        case .word(_, _):
            words.remove(item)
        case .thread(_, _):
            threads.remove(item)
        }
    }
    
    /// Returns the mute reason for an event, using cache with expiration validation.
    func event_muted_reason(_ ev: NostrEvent) -> MuteItem? {
        if let cached = self.muted_notes_cache[ev.id] {
            // Re-validate cached mute status in case it expired
            if case .muted(let reason) = cached {
                if !reason.isActive() {
                    // Mute expired - recompute to check for other active mute reasons
                    self.muted_notes_cache[ev.id] = .not_muted
                    if let fresh = self.compute_event_muted_reason(ev) {
                        self.muted_notes_cache[ev.id] = .muted(reason: fresh)
                        return fresh
                    }
                    return nil
                }
                return reason
            }
            return cached.mute_reason()
        }
        if let reason = self.compute_event_muted_reason(ev) {
            self.muted_notes_cache[ev.id] = .muted(reason: reason)
            return reason
        }
        self.muted_notes_cache[ev.id] = .not_muted
        return nil
    }


    /// Check if an event is muted given a collection of ``MutedItem``.
    ///
    /// - Parameter ev: The ``NostrEvent`` that you want to check the muted reason for.
    /// - Returns: The ``MuteItem`` that matched the event (if active). Or `nil` if the event is not muted.
    func compute_event_muted_reason(_ ev: NostrEvent) -> MuteItem? {
        // Events from the current user should not be muted.
        guard self.user_keypair.pubkey != ev.pubkey else { return nil }

        // Check if user is muted (and active)
        let check_user_item = MuteItem.user(ev.pubkey, nil)
        if let stored = users.first(where: { $0 == check_user_item }), stored.isActive() {
            return stored
        }

        // Check if hashtag is muted (and active)
        for hashtag in ev.referenced_hashtags {
            let check_hashtag_item = MuteItem.hashtag(hashtag, nil)
            if let stored = hashtags.first(where: { $0 == check_hashtag_item }), stored.isActive() {
                return stored
            }
        }

        // Check if thread is muted (and active)
        for thread_id in ev.referenced_ids {
            let check_thread_item = MuteItem.thread(thread_id, nil)
            if let stored = threads.first(where: { $0 == check_thread_item }), stored.isActive() {
                return stored
            }
        }

        // Check if word is muted (and active)
        if let content: String = ev.maybe_get_content(self.user_keypair)?.lowercased() {
            for word in words {
                if case .word(let string, _) = word, word.isActive() {
                    if content.contains(string.lowercased()) {
                        return word
                    }
                }
            }
        }

        return nil
    }
    
    enum EventMuteStatus {
        case muted(reason: MuteItem)
        case not_muted
        
        func mute_reason() -> MuteItem? {
            switch self {
                case .muted(reason: let reason):
                    return reason
                case .not_muted:
                    return nil
            }
        }
    }
}
