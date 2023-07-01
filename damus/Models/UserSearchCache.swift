//
//  UserSearchCache.swift
//  damus
//
//  Created by Terry Yiu on 6/27/23.
//

import Foundation

/// Cache of searchable users by name, display_name, NIP-05 identifier, or own contact list petname.
/// Optimized for fast searches of substrings by using a Trie.
/// Optimal for performing user searches that could be initiated by typing quickly on a keyboard into a text input field.
class UserSearchCache {
    private let trie = Trie<String>()

    func search(key: String) -> [String] {
        let results = trie.find(key: key)
        return results
    }

    /// Computes the differences between an old profile, if it exists, and a new profile, and updates the user search cache accordingly.
    func updateProfile(id: String, profiles: Profiles, oldProfile: Profile?, newProfile: Profile) {
        // Remove searchable keys tied to the old profile if they differ from the new profile
        // to keep the trie clean without empty nodes while avoiding excessive graph searching.
        if let oldProfile {
            if let oldName = oldProfile.name, newProfile.name?.caseInsensitiveCompare(oldName) != .orderedSame {
                trie.remove(key: oldName.lowercased(), value: id)
            }
            if let oldDisplayName = oldProfile.display_name, newProfile.display_name?.caseInsensitiveCompare(oldDisplayName) != .orderedSame {
                trie.remove(key: oldDisplayName.lowercased(), value: id)
            }
            if let oldNip05 = oldProfile.nip05, newProfile.nip05?.caseInsensitiveCompare(oldNip05) != .orderedSame {
                trie.remove(key: oldNip05.lowercased(), value: id)
            }
        }

        addProfile(id: id, profiles: profiles, profile: newProfile)
    }

    /// Adds a profile to the user search cache.
    private func addProfile(id: String, profiles: Profiles, profile: Profile) {
        // Searchable by name.
        if let name = profile.name {
            trie.insert(key: name.lowercased(), value: id)
        }

        // Searchable by display name.
        if let displayName = profile.display_name {
            trie.insert(key: displayName.lowercased(), value: id)
        }

        // Searchable by NIP-05 identifier.
        if let nip05 = profiles.is_validated(id) {
            trie.insert(key: "\(nip05.username.lowercased())@\(nip05.host.lowercased())", value: id)
        }
    }

    /// Computes the diffences between an old contacts event and a new contacts event for our own user, and updates the search cache accordingly.
    func updateOwnContactsPetnames(id: String, oldEvent: NostrEvent?, newEvent: NostrEvent) {
        guard newEvent.known_kind == .contacts && newEvent.pubkey == id else {
            return
        }

        var petnames: [String: String] = [:]

        // Gets all petnames from our new contacts list.
        newEvent.tags.forEach { tag in
            guard tag.count >= 4 && tag[0] == "p" else {
                return
            }

            let pubkey = tag[1]
            let petname = tag[3]

            petnames[pubkey] = petname
        }

        // Compute the diff with the old contacts list, if it exists,
        // mark the ones that are the same to not be removed from the user search cache,
        // and remove the old ones that are different from the user search cache.
        if let oldEvent, oldEvent.known_kind == .contacts && oldEvent.pubkey == id {
            oldEvent.tags.forEach { tag in
                guard tag.count >= 4 && tag[0] == "p" else {
                    return
                }

                let pubkey = tag[1]
                let oldPetname = tag[3]

                if let newPetname = petnames[pubkey] {
                    if newPetname.caseInsensitiveCompare(oldPetname) == .orderedSame {
                        petnames.removeValue(forKey: pubkey)
                    } else {
                        trie.remove(key: oldPetname, value: pubkey)
                    }
                } else {
                    trie.remove(key: oldPetname, value: pubkey)
                }
            }
        }

        // Add the new petnames to the user search cache.
        for (pubkey, petname) in petnames {
            trie.insert(key: petname, value: pubkey)
        }
    }
}
