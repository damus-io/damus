//
//  FriendFilter.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-11-24.
//

import Foundation

enum FriendFilter: String, StringCodable {
    case all
    case friends
    
    init?(from string: String) {
        guard let ff = FriendFilter(rawValue: string) else {
            return nil
        }
        
        self = ff
    }
    
    func to_string() -> String {
        self.rawValue
    }
    
    func filter(contacts: Contacts, pubkey: Pubkey) -> Bool {
        switch self {
        case .all:
            return true
        case .friends:
            return contacts.is_friend_or_self(pubkey)
        }
    }
}
