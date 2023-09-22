//
//  Bech32Object.swift
//  damus
//
//  Created by William Casarin on 2023-01-28.
//

import Foundation


enum Bech32Object {
    case nsec(Privkey)
    case npub(Pubkey)
    case note(NoteId)
    case nscript([UInt8])
    
    static func parse(_ str: String) -> Bech32Object? {
        guard let decoded = try? bech32_decode(str) else {
            return nil
        }
        
        if decoded.hrp == "npub" {
            return .npub(Pubkey(decoded.data))
        } else if decoded.hrp == "nsec" {
            return .nsec(Privkey(decoded.data))
        } else if decoded.hrp == "note" {
            return .note(NoteId(decoded.data))
        } else if decoded.hrp == "nscript" {
            return .nscript(decoded.data.bytes)
        }
        
        return nil
    }
}
