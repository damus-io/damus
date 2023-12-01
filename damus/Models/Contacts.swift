//
//  Contacts.swift
//  damus
//
//  Created by William Casarin on 2022-05-14.
//

import Foundation


class Contacts {
    private var friends: Set<Pubkey> = Set()
    private var friend_of_friends: Set<Pubkey> = Set()
    /// Tracks which friends are friends of a given pubkey.
    private var pubkey_to_our_friends = [Pubkey : Set<Pubkey>]()
    private var muted: Set<Pubkey> = Set()

    let our_pubkey: Pubkey
    var event: NostrEvent?
    var mutelist: NostrEvent?
    
    init(our_pubkey: Pubkey) {
        self.our_pubkey = our_pubkey
    }
    
    func is_muted(_ pk: Pubkey) -> Bool {
        return muted.contains(pk)
    }
    
    func set_mutelist(_ ev: NostrEvent) {
        let oldlist = self.mutelist
        self.mutelist = ev

        let old = oldlist.map({ ev in Set(ev.referenced_pubkeys) }) ?? Set<Pubkey>()
        let new = Set(ev.referenced_pubkeys)
        let diff = old.symmetricDifference(new)
        
        var new_mutes = Set<Pubkey>()
        var new_unmutes = Set<Pubkey>()

        for d in diff {
            if new.contains(d) {
                new_mutes.insert(d)
            } else {
                new_unmutes.insert(d)
            }
        }

        // TODO: set local mutelist here
        self.muted = Set(ev.referenced_pubkeys)

        if new_mutes.count > 0 {
            notify(.new_mutes(new_mutes))
        }
        
        if new_unmutes.count > 0 {
            notify(.new_unmutes(new_unmutes))
        }
    }
    
    func remove_friend(_ pubkey: Pubkey) {
        friends.remove(pubkey)

        pubkey_to_our_friends.forEach {
            pubkey_to_our_friends[$0.key]?.remove(pubkey)
        }
    }
    
    func get_friend_list() -> Set<Pubkey> {
        return friends
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
        friends.insert(pubkey)
    }
    
    func add_friend_contact(_ contact: NostrEvent) {
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
        return friend_of_friends.contains(pubkey)
    }
    
    func is_in_friendosphere(_ pubkey: Pubkey) -> Bool {
        return friends.contains(pubkey) || friend_of_friends.contains(pubkey)
    }

    func is_friend(_ pubkey: Pubkey) -> Bool {
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
        return Array((pubkey_to_our_friends[pubkey] ?? Set()))
    }
}
