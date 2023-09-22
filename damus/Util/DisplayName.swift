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
}


func parse_display_name(profile: Profile?, pubkey: Pubkey) -> DisplayName {
    if pubkey == ANON_PUBKEY {
        return .one(NSLocalizedString("Anonymous", comment: "Placeholder display name of anonymous user."))
    }
    
    guard let profile else {
        return .one(abbrev_bech32_pubkey(pubkey: pubkey))
    }
    
    let name = profile.name?.isEmpty == false ? profile.name : nil
    let disp_name = profile.display_name?.isEmpty == false ? profile.display_name : nil
    
    if let name, let disp_name, name != disp_name {
        return .both(username: name, displayName: disp_name)
    }
    
    if let one = name ?? disp_name {
        return .one(one)
    }
    
    return .one(abbrev_bech32_pubkey(pubkey: pubkey))
}

func abbrev_bech32_pubkey(pubkey: Pubkey) -> String {
    return abbrev_pubkey(String(pubkey.npub.dropFirst(4)))
}
