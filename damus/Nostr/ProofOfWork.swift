//
//  ProofOfWork.swift
//  damus
//
//  Created by William Casarin on 2022-04-11.
//

import Foundation


func zero_bits(_ argb: UInt8) -> Int
{
    var b = argb
    var n: Int = 0;

    if b == 0 {
        return 8;
    }

    while true {
        b >>= 1;
        if b != 0 {
            n += 1;
        } else {
            break
        }
    }

    return 7-n;
}

func count_hash_leading_zero_bits(_ hash: String) -> Int?
{
    guard let decoded = hex_decode(hash) else {
        return nil
    }
    return count_leading_zero_bits(decoded)
}

/* find the number of leading zero bits in a hash */
func count_leading_zero_bits(_ hash: [UInt8]) -> Int
{
    var bits: Int = 0
    var total: Int = 0

    for c in hash {
        bits = zero_bits(c)
        total += bits
        if (bits != 8) {
            break
        }
    }

    return total
}


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


