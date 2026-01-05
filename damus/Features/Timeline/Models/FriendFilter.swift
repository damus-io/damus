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
    
    @MainActor
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
                return NSLocalizedString("All", comment: "Human-readable short description of the 'trusted network filter' when it is disabled, and therefore is showing all content.")
            case .friends_of_friends:
                return NSLocalizedString("Trusted Network", comment: "Human-readable short description of the 'trusted network filter' when it is enabled, and therefore showing content from only the trusted network.")
        }
    }
}
