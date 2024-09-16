//
//  FriendFilter.swift
//  damus
//
//  Created by Daniel D’Aquino on 2023-11-24.
//

import Foundation

enum FriendFilter: String, StringCodable {
    case all
    case friends_of_friends
    
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
        case .friends_of_friends:
            return contacts.is_in_friendosphere(pubkey)
        }
    }
    
    func description() -> String {
        switch self {
            case .all:
                return NSLocalizedString("All", comment: "Human-readable short description of the 'friends filter' when it is set to 'all'")
            case .friends_of_friends:
                return NSLocalizedString("Friends of friends", comment: "Human-readable short description of the 'friends filter' when it is set to 'friends-of-friends'")
        }
    }
}
