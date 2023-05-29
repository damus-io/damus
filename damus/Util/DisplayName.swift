//
//  DisplayName.swift
//  damus
//
//  Created by William Casarin on 2023-03-14.
//

import Foundation


struct BothNames {
    let username: String
    let display_name: String
}

enum DisplayName {
    case both(BothNames)
    case one(String)
    
    var display_name: String {
        switch self {
        case .one(let one):
            return one
        case .both(let b):
            return b.display_name
        }
    }
    
    var username: String {
        switch self {
        case .one(let one):
            return one
        case .both(let b):
            return b.username
        }
    }
}


func parse_display_name(profile: Profile?, pubkey: String) -> DisplayName {
    if pubkey == "anon" {
        return .one(NSLocalizedString("Anonymous", comment: "Placeholder display name of anonymous user."))
    }
    
    guard let profile else {
        return .one(abbrev_bech32_pubkey(pubkey: pubkey))
    }
    
    let name = profile.name?.isEmpty == false ? profile.name : nil
    let disp_name = profile.display_name?.isEmpty == false ? profile.display_name : nil
    
    if let name, let disp_name, name != disp_name {
        return .both(BothNames(username: name, display_name: disp_name))
    }
    
    if let one = name ?? disp_name {
        return .one(one)
    }
    
    return .one(abbrev_bech32_pubkey(pubkey: pubkey))
}

func abbrev_bech32_pubkey(pubkey: String) -> String {
    let pk = bech32_nopre_pubkey(pubkey) ?? pubkey
    return abbrev_pubkey(pk)
}
