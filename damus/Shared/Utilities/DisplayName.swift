//
//  DisplayName.swift
//  damus
//
//  Created by William Casarin on 2023-03-14.
//

import Foundation

enum DisplayName: Equatable {
    case both(username: String, displayName: String)
    case one(String)

    init (profile: Profile?, pubkey: Pubkey) {
        self = parse_display_name(name: profile?.name, display_name: profile?.display_name, pubkey: pubkey)
    }

    init (name: String?, display_name: String?, pubkey: Pubkey) {
        self = parse_display_name(name: name, display_name: display_name, pubkey: pubkey)
    }

    var displayName: String {
        switch self {
        case .one(let one):
            return one
        case .both(username: _, displayName: let displayName):
            return displayName
        }
    }
    
    var username: String {
        switch self {
        case .one(let one):
            return one
        case .both(username: let username, displayName: _):
            return username
        }
    }

    func nameComponents() -> PersonNameComponents {
        var components = PersonNameComponents()
        switch self {
        case .one(let one):
            components.nickname = one
            return components
        case .both(username: let username, displayName: let displayName):
            components.nickname = username
            let names = displayName.split(separator: " ")
            if let name = names.first {
                components.givenName = String(name)
                components.familyName = names.dropFirst().joined(separator: " ")
            }
            return components
        }
    }
}


/// Parses profile name fields into a DisplayName, with graceful fallback to abbreviated bech32 pubkey.
///
/// Resolution order:
/// 1. If both `name` and `display_name` exist and differ → `.both(username:displayName:)`
/// 2. If only one of `name` or `display_name` exists → `.one(thatValue)`
/// 3. If neither exists (profile not found or empty) → `.one(abbreviated_npub)`
///
/// The abbreviated npub format (e.g., "1abc1234:xyz89012") is used when no profile metadata
/// is available. This commonly occurs in push notifications when the sender's profile
/// hasn't been fetched from relays yet.
func parse_display_name(name: String?, display_name: String?, pubkey: Pubkey) -> DisplayName {
    if pubkey == ANON_PUBKEY {
        return .one(NSLocalizedString("Anonymous", comment: "Placeholder display name of anonymous user."))
    }

    // Early return: no profile data available, fall back to abbreviated bech32
    if name == nil && display_name == nil {
        return .one(abbrev_bech32_pubkey(pubkey: pubkey))
    }

    // Treat empty strings as nil for cleaner logic
    let name = name?.isEmpty == false ? name : nil
    let disp_name = display_name?.isEmpty == false ? display_name : nil

    if let name, let disp_name, name != disp_name {
        return .both(username: name, displayName: disp_name)
    }

    if let one = name ?? disp_name {
        return .one(one)
    }

    // Final fallback: abbreviated bech32 pubkey
    return .one(abbrev_bech32_pubkey(pubkey: pubkey))
}

/// Creates an abbreviated display string from a bech32 pubkey.
/// Strips the "npub" prefix and abbreviates to "prefix:suffix" format.
/// Example: npub1abc123...xyz789 → "1abc1234:xyz78912"
func abbrev_bech32_pubkey(pubkey: Pubkey) -> String {
    // Drop the "npub" prefix (4 chars) before abbreviating
    return abbrev_identifier(String(pubkey.npub.dropFirst(4)))
}

/// Abbreviates a string to "prefix:suffix" format for compact display.
/// Default shows 8 characters from each end.
/// Example: "abcdefghijklmnopqrstuvwxyz" → "abcdefgh:stuvwxyz"
func abbrev_identifier(_ pubkey: String, amount: Int = 8) -> String {
    return pubkey.prefix(amount) + ":" + pubkey.suffix(amount)
}
