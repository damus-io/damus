//
//  MutelistManager.swift
//  damus
//
//  Created by Charlie Fish on 1/28/24.
//

import Foundation

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
    
    init(user_keypair: Keypair) {
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

    func is_muted(_ item: MuteItem) -> Bool {
        switch item {
        case .user(_, _):
            return users.contains(item)
        case .hashtag(_, _):
            return hashtags.contains(item)
        case .word(_, _):
            return words.contains(item)
        case .thread(_, _):
            return threads.contains(item)
        }
    }

    func is_event_muted(_ ev: NostrEvent) -> Bool {
        return self.event_muted_reason(ev) != nil
    }

    func set_mutelist(_ ev: NostrEvent) {
        let oldlist = self.event
        self.event = ev

        let old: Set<MuteItem> = oldlist?.mute_list ?? Set<MuteItem>()
        let new: Set<MuteItem> = ev.mute_list ?? Set<MuteItem>()
        let diff = old.symmetricDifference(new)

        var new_mutes = Set<MuteItem>()
        var new_unmutes = Set<MuteItem>()

        for d in diff {
            if new.contains(d) {
                add_mute_item(d)
                new_mutes.insert(d)
            } else {
                remove_mute_item(d)
                new_unmutes.insert(d)
            }
        }

        if new_mutes.count > 0 {
            notify(.new_mutes(new_mutes))
        }

        if new_unmutes.count > 0 {
            notify(.new_unmutes(new_unmutes))
        }
    }

    private func add_mute_item(_ item: MuteItem) {
        switch item {
        case .user(_, _):
            users.insert(item)
        case .hashtag(_, _):
            hashtags.insert(item)
        case .word(_, _):
            words.insert(item)
        case .thread(_, _):
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
    
    func event_muted_reason(_ ev: NostrEvent) -> MuteItem? {
        if let cached_mute_status = self.muted_notes_cache[ev.id] {
            return cached_mute_status.mute_reason()
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
    /// - Returns: The ``MuteItem`` that matched the event. Or `nil` if the event is not muted.
    func compute_event_muted_reason(_ ev: NostrEvent) -> MuteItem? {
        // Events from the current user should not be muted.
        guard self.user_keypair.pubkey != ev.pubkey else { return nil }

        // Check if user is muted
        let check_user_item = MuteItem.user(ev.pubkey, nil)
        if users.contains(check_user_item) {
            return check_user_item
        }

        // Check if hashtag is muted
        for hashtag in ev.referenced_hashtags {
            let check_hashtag_item = MuteItem.hashtag(hashtag, nil)
            if hashtags.contains(check_hashtag_item) {
                return check_hashtag_item
            }
        }

        // Check if thread is muted
        for thread_id in ev.referenced_ids {
            let check_thread_item = MuteItem.thread(thread_id, nil)
            if threads.contains(check_thread_item) {
                return check_thread_item
            }
        }

        // Check if word is muted
        if let content: String = ev.maybe_get_content(self.user_keypair)?.lowercased() {
            for word in words {
                if case .word(let string, _) = word {
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
