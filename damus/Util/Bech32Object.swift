//
//  Bech32Object.swift
//  damus
//
//  Created by William Casarin on 2023-01-28.
//

import Foundation


enum Bech32Object {
    case nsec(String)
    case npub(String)
    case note(String)
    
    static func parse(_ str: String) -> Bech32Object? {
        guard let decoded = try? bech32_decode(str) else {
            return nil
        }
        
        if decoded.hrp == "npub" {
            return .npub(hex_encode(decoded.data))
        } else if decoded.hrp == "nsec" {
            return .nsec(hex_encode(decoded.data))
        } else if decoded.hrp == "note" {
            return .note(hex_encode(decoded.data))
        }
        
        return nil
    }
}
