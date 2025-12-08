//
//  NIP05.swift
//  damus
//
//  Created by William Casarin on 2023-01-04.
//

import Foundation

struct NIP05: Equatable {
    let username: String
    let host: String
    
    var url: URL? {
        URL(string: "https://\(host)/.well-known/nostr.json?name=\(username)")
    }
    
    var siteUrl: URL? {
        URL(string: "https://\(host)")
    }
    
    static func parse(_ nip05: String) -> NIP05? {
        let parts = nip05.split(separator: "@")
        guard parts.count == 2 else {
            return nil
        }
        return NIP05(username: String(parts[0]), host: String(parts[1]))
    }
}


struct NIP05Response: Decodable {
    let names: [String: Pubkey]
}

func fetch_nip05(nip05: NIP05) async -> NIP05Response? {
    guard let url = nip05.url else {
        return nil
    }

    print("fetching nip05 \(url.absoluteString)")
    guard let ret = try? await URLSession.shared.data(from: url) else {
        return nil
    }
    let dat = ret.0
    
    guard let decoded = try? JSONDecoder().decode(NIP05Response.self, from: dat) else {
        return nil
    }
    
    return decoded
}

func validate_nip05(pubkey: Pubkey, nip05_str: String) async -> NIP05? {
    guard let nip05 = NIP05.parse(nip05_str) else {
        return nil
    }

    guard let decoded = await fetch_nip05(nip05: nip05) else {
        return nil
    }

    guard let stored_pk = decoded.names[nip05.username] else {
        return nil
    }

    guard stored_pk == pubkey else {
        return nil
    }

    return nip05
}

/// Consolidated NIP-05 domain matching helpers to avoid code duplication
struct NIP05DomainHelpers {

    /// Checks if a pubkey's NIP-05 matches the given domain (case-insensitive)
    /// Prefers validated NIP-05 if present, falls back to raw NIP-05 on profile
    @MainActor
    static func matches_domain(_ pubkey: Pubkey, domain: String, profiles: Profiles) -> Bool {
        // Prefer validated nip05 if present; fallback to raw nip05 on profile.
        if let validated = profiles.is_validated(pubkey),
           validated.host.caseInsensitiveCompare(domain) == .orderedSame {
            return true
        }

        guard let profile = try? profiles.lookup(id: pubkey),
              let nip05_str = profile.nip05,
              let nip05 = NIP05.parse(nip05_str) else {
            return false
        }

        return nip05.host.caseInsensitiveCompare(domain) == .orderedSame
    }

    /// Gets all validated authors for a domain
    @MainActor
    static func validated_authors_for_domain(domain: String, profiles: Profiles) -> Set<Pubkey> {
        let validated = profiles.nip05_pubkey
        return Set(validated.compactMap { (nip05_str, pk) in
            guard let nip05 = NIP05.parse(nip05_str),
                  nip05.host.caseInsensitiveCompare(domain) == .orderedSame else {
                return nil
            }
            return pk
        })
    }

    /// Scans ALL cached profiles in nostrdb for matching domain (for discovery)
    ///
    /// This enables discovery of users with a specific NIP-05 domain without requiring
    /// them to be in your social graph. It scans locally cached metadata events (kind:0)
    /// which is fast and doesn't require network requests.
    ///
    /// - Parameters:
    ///   - domain: The NIP-05 domain to match (e.g., "damus.io")
    ///   - ndb: The nostrdb instance to query
    ///   - limit: Maximum number of profiles to scan (default: 10000)
    /// - Returns: Set of pubkeys with matching NIP-05 domain
    static func scan_all_cached_profiles(domain: String, ndb: Ndb, limit: Int = 10000) -> Set<Pubkey> {
        var matching = Set<Pubkey>()

        var nostrFilter = NostrFilter()
        nostrFilter.kinds = [.metadata]
        nostrFilter.limit = UInt32(limit)

        do {
            let ndbFilter = try NdbFilter(from: nostrFilter)
            let noteKeys = try ndb.query(filters: [ndbFilter], maxResults: limit)

            for noteKey in noteKeys {
                // Get the pubkey from the metadata note
                guard let pubkey: Pubkey = try ndb.lookup_note_by_key(noteKey, borrow: {
                    switch $0 {
                    case .none: return nil
                    case .some(let note): return note.pubkey
                    }
                }) else {
                    continue
                }

                // Look up the profile and check domain match
                let matches: Bool = (try? ndb.lookup_profile(pubkey, borrow: {
                    switch $0 {
                    case .none: return false
                    case .some(let record):
                        guard let profile = record.profile,
                              let nip05_str = profile.nip05,
                              let nip05 = NIP05.parse(nip05_str) else {
                            return false
                        }
                        return nip05.host.caseInsensitiveCompare(domain) == .orderedSame
                    }
                })) ?? false

                if matches {
                    matching.insert(pubkey)
                }
            }
        } catch {
            print("Failed to scan cached profiles: \(error)")
        }

        return matching
    }

    /// Gets authors for a domain based on the friend filter mode
    ///
    /// Two modes of operation:
    /// - WOT ON (.friends_of_friends): Filter to only friends-of-friends with matching domain
    /// - WOT OFF (.all): Scan ALL cached profiles for discovery without social graph requirement
    ///
    /// - Parameters:
    ///   - domain: The NIP-05 domain to match
    ///   - friend_filter: Whether to use WOT filtering or show all
    ///   - contacts: User's contacts for friend-of-friends lookup
    ///   - profiles: Profiles cache for validated NIP-05 lookups
    ///   - ndb: Nostrdb instance for scanning cached profiles
    /// - Returns: Set of pubkeys to query events from
    @MainActor
    static func authors_for_domain(domain: String, friend_filter: FriendFilter, contacts: Contacts, profiles: Profiles, ndb: Ndb) async -> Set<Pubkey> {
        var authors = Set<Pubkey>()

        switch friend_filter {
        case .friends_of_friends:
            // WOT mode: Only show users in your trusted network
            for pubkey in contacts.get_friend_of_friends_list() where matches_domain(pubkey, domain: domain, profiles: profiles) {
                authors.insert(pubkey)
            }
        case .all:
            // Discovery mode: Scan ALL cached profiles to find users by domain
            // Run off the main thread — scans up to 10k profiles in nostrdb
            authors = await Task.detached {
                scan_all_cached_profiles(domain: domain, ndb: ndb)
            }.value

            // Fallback to validated authors if no cached profiles found
            if authors.isEmpty {
                authors = validated_authors_for_domain(domain: domain, profiles: profiles)
            }
        }

        return authors
    }

    /// Gets domain authors ordered by those with events first, filtered by friend filter
    ///
    /// Orders authors to prioritize those who already have loaded events, making the header
    /// feel responsive by showing profile pictures immediately. This is used for the header
    /// display that shows "Notes from X, Y & Z".
    ///
    /// - Parameters:
    ///   - domain: The NIP-05 domain to match
    ///   - friend_filter: WOT mode for additional filtering
    ///   - contacts: User's contacts for friend-of-friends check
    ///   - profiles: Profiles cache for domain matching
    ///   - eventPubkeys: Pubkeys from already-loaded events (shown first)
    ///   - filterAuthors: Pubkeys from the query filter (queried authors)
    /// - Returns: Ordered array of pubkeys with domain match, prioritizing those with events
    @MainActor
    static func ordered_domain_authors(
        domain: String,
        friend_filter: FriendFilter,
        contacts: Contacts,
        profiles: Profiles,
        eventPubkeys: [Pubkey],
        filterAuthors: [Pubkey]?
    ) -> [Pubkey] {
        // Prioritize authors with loaded events to make header feel responsive
        let pubkeys = eventPubkeys + (filterAuthors ?? [])
        var seen = Set<Pubkey>()
        let orderedUnique = pubkeys.filter { seen.insert($0).inserted }

        // Filter to only those matching the domain
        let matching = orderedUnique.filter { pk in
            matches_domain(pk, domain: domain, profiles: profiles)
        }

        // Additional WOT filtering if enabled
        if friend_filter == .friends_of_friends {
            return matching.filter { contacts.is_in_friendosphere($0) }
        }

        return matching
    }
}
