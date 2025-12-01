//
//  Contacts.swift
//  damus
//
//  Created by William Casarin on 2022-05-14.
//

import Foundation

class Contacts {
    private let lock = NSLock()
    private var friends: Set<Pubkey> = Set()
    private var friend_of_friends: Set<Pubkey> = Set()
    /// Tracks which friends are friends of a given pubkey.
    private var pubkey_to_our_friends = [Pubkey : Set<Pubkey>]()

    let our_pubkey: Pubkey
    var delegate: ContactsDelegate? = nil
    var event: NostrEvent? {
        didSet {
            guard let event else { return }
            self.delegate?.latest_contact_event_changed(new_event: event)
        }
    }

    init(our_pubkey: Pubkey) {
        self.our_pubkey = our_pubkey
    }

    func remove_friend(_ pubkey: Pubkey) {
        lock.lock()
        defer { lock.unlock() }
        friends.remove(pubkey)

        for key in pubkey_to_our_friends.keys {
            pubkey_to_our_friends[key]?.remove(pubkey)
        }
    }
    
    func get_friend_list() -> Set<Pubkey> {
        lock.lock()
        defer { lock.unlock() }
        return friends
    }

    func get_friend_of_friends_list() -> Set<Pubkey> {
        lock.lock()
        defer { lock.unlock() }
        return friend_of_friends
    }

    func get_followed_hashtags() -> Set<String> {
        guard let ev = self.event else { return Set() }
        return Set(ev.referenced_hashtags.map({ $0.hashtag }))
    }
    
    func follows(hashtag: Hashtag) -> Bool {
        guard let ev = self.event else { return false }
        return ev.referenced_hashtags.first(where: { $0 == hashtag }) != nil
    }

    func add_friend_pubkey(_ pubkey: Pubkey) {
        lock.lock()
        defer { lock.unlock() }
        friends.insert(pubkey)
    }
    
    func add_friend_contact(_ contact: NostrEvent) {
        lock.lock()
        defer { lock.unlock() }
        friends.insert(contact.pubkey)
        for pk in contact.referenced_pubkeys {
            friend_of_friends.insert(pk)

            // Exclude themself and us.
            if contact.pubkey != our_pubkey && contact.pubkey != pk {
                if pubkey_to_our_friends[pk] == nil {
                    pubkey_to_our_friends[pk] = Set<Pubkey>()
                }

                pubkey_to_our_friends[pk]?.insert(contact.pubkey)
            }
        }
    }
    
    func is_friend_of_friend(_ pubkey: Pubkey) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return friend_of_friends.contains(pubkey)
    }
    
    func is_in_friendosphere(_ pubkey: Pubkey) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return friends.contains(pubkey) || friend_of_friends.contains(pubkey)
    }

    func is_friend(_ pubkey: Pubkey) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return friends.contains(pubkey)
    }
    
    func is_friend_or_self(_ pubkey: Pubkey) -> Bool {
        return pubkey == our_pubkey || is_friend(pubkey)
    }
    
    func follow_state(_ pubkey: Pubkey) -> FollowState {
        return is_friend(pubkey) ? .follows : .unfollows
    }

    /// Gets the list of pubkeys of our friends who follow the given pubkey.
    func get_friended_followers(_ pubkey: Pubkey) -> [Pubkey] {
        lock.lock()
        defer { lock.unlock() }
        return Array((pubkey_to_our_friends[pubkey] ?? Set()))
    }

    var friend_filter: (NostrEvent) -> Bool {
        { [weak self] ev in
            guard let self else { return false }
            return self.is_friend(ev.pubkey)
        }
    }
}

/// Delegate protocol for `Contacts`. Use this to listen to significant updates from a `Contacts` instance
protocol ContactsDelegate {
    func latest_contact_event_changed(new_event: NostrEvent)
}
