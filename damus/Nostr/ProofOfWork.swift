//
//  ProofOfWork.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation

func char_to_hex(_ c: UInt8) -> UInt8?
{
    // 0 && 9
    if (c >= 48 && c <= 57) {
        return c - 48 // 0
    }
    // a && f
    if (c >= 97 && c <= 102) {
        return c - 97 + 10;
    }
    // A && F
    if (c >= 65 && c <= 70) {
        return c - 65 + 10;
    }
    return nil;
}

@discardableResult
func hex_decode(_ str: String) -> [UInt8]?
{
    if str.count == 0 {
        return nil
    }
    var ret: [UInt8] = []
    let chars = Array(str.utf8)
    var i: Int = 0
    for c in zip(chars, chars[1...]) {
        i += 1

        if i % 2 == 0 {
            continue
        }

        guard let c1 = char_to_hex(c.0) else {
            return nil
        }

        guard let c2 = char_to_hex(c.1) else {
            return nil
        }

        ret.append((c1 << 4) | c2)
    }

    return ret
}


