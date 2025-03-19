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


func parse_display_name(name: String?, display_name: String?, pubkey: Pubkey) -> DisplayName {
    if pubkey == ANON_PUBKEY {
        return .one(NSLocalizedString("Anonymous", comment: "Placeholder display name of anonymous user."))
    }

    if name == nil && display_name == nil {
        return .one(abbrev_bech32_pubkey(pubkey: pubkey))
    }

    let name = name?.isEmpty == false ? name : nil
    let disp_name = display_name?.isEmpty == false ? display_name : nil
    
    if let name, let disp_name, name != disp_name {
        return .both(username: name, displayName: disp_name)
    }
    
    if let one = name ?? disp_name {
        return .one(one)
    }
    
    return .one(abbrev_bech32_pubkey(pubkey: pubkey))
}

func abbrev_bech32_pubkey(pubkey: Pubkey) -> String {
    return abbrev_identifier(String(pubkey.npub.dropFirst(4)))
}

func abbrev_identifier(_ pubkey: String, amount: Int = 8) -> String {
    return pubkey.prefix(amount) + ":" + pubkey.suffix(amount)
}
