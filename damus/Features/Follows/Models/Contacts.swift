//
//  Contacts.swift
//  damus
//
//  Created by William Casarin on 2022-05-14.
//

import Foundation

/// Manages the user's contact list including friends and friends-of-friends relationships.
///
/// This class is thread-safe and can be accessed from multiple concurrent contexts.
/// All mutable state is protected by an internal lock to prevent race conditions
/// during operations like "Follow All" in onboarding.
class Contacts {
    /// Lock to ensure thread-safe access to mutable state.
    /// This prevents race conditions when multiple threads access contacts concurrently
    /// (e.g., during "Follow All" in onboarding which fires multiple async follow operations).
    private let lock = NSLock()

    private var friends: Set<Pubkey> = Set()
    private var friend_of_friends: Set<Pubkey> = Set()
    /// Tracks which friends are friends of a given pubkey.
    private var pubkey_to_our_friends = [Pubkey : Set<Pubkey>]()

    private var _event: NostrEvent? = nil
    private var _delegate: ContactsDelegate? = nil

    let our_pubkey: Pubkey

    var delegate: ContactsDelegate? {
        get { lock.withLock { _delegate } }
        set { lock.withLock { _delegate = newValue } }
    }

    var event: NostrEvent? {
        get { lock.withLock { _event } }
        set {
            // Capture delegate and event inside lock, but call delegate outside
            // to avoid potential deadlocks
            let (delegateToNotify, eventToNotify): (ContactsDelegate?, NostrEvent?) = lock.withLock {
                _event = newValue
                return (_delegate, newValue)
            }

            guard let event = eventToNotify else { return }
            delegateToNotify?.latest_contact_event_changed(new_event: event)
        }
    }

    init(our_pubkey: Pubkey) {
        self.our_pubkey = our_pubkey
    }

    /// Removes a pubkey from the friend list and cleans up friend-of-friend mappings.
    /// - Parameter pubkey: The pubkey to remove from the friend list.
    func remove_friend(_ pubkey: Pubkey) {
        lock.withLock {
            friends.remove(pubkey)

            pubkey_to_our_friends.forEach {
                pubkey_to_our_friends[$0.key]?.remove(pubkey)
            }
        }
    }

    /// Returns a snapshot of the current friend list.
    /// - Returns: A set of pubkeys representing the user's friends.
    func get_friend_list() -> Set<Pubkey> {
        return lock.withLock { friends }
    }

    /// Returns a snapshot of the current friends-of-friends list.
    /// - Returns: A set of pubkeys that are followed by the user's friends.
    func get_friend_of_friends_list() -> Set<Pubkey> {
        return lock.withLock { friend_of_friends }
    }

    /// Returns all hashtags the user is following.
    /// - Returns: A set of hashtag strings extracted from the contact event.
    func get_followed_hashtags() -> Set<String> {
        guard let ev = self.event else { return Set() }
        return Set(ev.referenced_hashtags.map({ $0.hashtag }))
    }

    /// Checks if the user follows a specific hashtag.
    /// - Parameter hashtag: The hashtag to check.
    /// - Returns: `true` if the user follows the hashtag, `false` otherwise.
    func follows(hashtag: Hashtag) -> Bool {
        guard let ev = self.event else { return false }
        return ev.referenced_hashtags.first(where: { $0 == hashtag }) != nil
    }

    /// Adds a pubkey to the friend list.
    /// - Parameter pubkey: The pubkey to add as a friend.
    func add_friend_pubkey(_ pubkey: Pubkey) {
        lock.withLock {
            _ = friends.insert(pubkey)
        }
    }

    /// Adds a contact event's pubkey as a friend and indexes their followed pubkeys as friends-of-friends.
    /// - Parameter contact: A contact list event from a friend.
    func add_friend_contact(_ contact: NostrEvent) {
        lock.withLock {
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
    }

    /// Checks if a pubkey is a friend-of-friend (followed by someone we follow).
    /// - Parameter pubkey: The pubkey to check.
    /// - Returns: `true` if the pubkey is a friend-of-friend, `false` otherwise.
    func is_friend_of_friend(_ pubkey: Pubkey) -> Bool {
        return lock.withLock { friend_of_friends.contains(pubkey) }
    }

    /// Checks if a pubkey is either a friend or a friend-of-friend.
    /// - Parameter pubkey: The pubkey to check.
    /// - Returns: `true` if the pubkey is in the "friendosphere", `false` otherwise.
    func is_in_friendosphere(_ pubkey: Pubkey) -> Bool {
        return lock.withLock {
            friends.contains(pubkey) || friend_of_friends.contains(pubkey)
        }
    }

    /// Checks if a pubkey is a direct friend.
    /// - Parameter pubkey: The pubkey to check.
    /// - Returns: `true` if the pubkey is a friend, `false` otherwise.
    func is_friend(_ pubkey: Pubkey) -> Bool {
        return lock.withLock { friends.contains(pubkey) }
    }

    /// Checks if a pubkey is either the user's own pubkey or a friend.
    /// - Parameter pubkey: The pubkey to check.
    /// - Returns: `true` if the pubkey is self or a friend, `false` otherwise.
    func is_friend_or_self(_ pubkey: Pubkey) -> Bool {
        return pubkey == our_pubkey || is_friend(pubkey)
    }

    /// Returns the follow state for a given pubkey.
    /// - Parameter pubkey: The pubkey to check.
    /// - Returns: `.follows` if the pubkey is a friend, `.unfollows` otherwise.
    func follow_state(_ pubkey: Pubkey) -> FollowState {
        return is_friend(pubkey) ? .follows : .unfollows
    }

    /// Gets the list of pubkeys of our friends who follow the given pubkey.
    func get_friended_followers(_ pubkey: Pubkey) -> [Pubkey] {
        return lock.withLock {
            Array((pubkey_to_our_friends[pubkey] ?? Set()))
        }
    }

    /// A filter closure that returns `true` for events authored by friends.
    /// Useful for filtering event streams to show only content from followed users.
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
