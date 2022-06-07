//
//  Bech32.swift
//
//  Modified by William Casarin in 2022
//  Created by Evolution Group Ltd on 12.02.2018.
//  Copyright © 2018 Evolution Group Ltd. All rights reserved.
//
//  Base32 address format for native v0-16 witness outputs implementation
//  https://github.com/bitcoin/bips/blob/master/bip-0173.mediawiki
//  Inspired by Pieter Wuille C++ implementation
import Foundation

/// Bech32 checksum implementation
fileprivate let gen: [UInt32] = [0x3b6a57b2, 0x26508e6d, 0x1ea119fa, 0x3d4233dd, 0x2a1462b3]
/// Bech32 checksum delimiter
fileprivate let checksumMarker: String = "1"
/// Bech32 character set for encoding
fileprivate let encCharset: Data = "qpzry9x8gf2tvdw0s3jn54khce6mua7l".data(using: .utf8)!
/// Bech32 character set for decoding
fileprivate let decCharset: [Int8] = [
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,
    15, -1, 10, 17, 21, 20, 26, 30,  7,  5, -1, -1, -1, -1, -1, -1,
    -1, 29, -1, 24, 13, 25,  9,  8, 23, -1, 18, 22, 31, 27, 19, -1,
    1,  0,  3, 16, 11, 28, 12, 14,  6,  4,  2, -1, -1, -1, -1, -1,
    -1, 29, -1, 24, 13, 25,  9,  8, 23, -1, 18, 22, 31, 27, 19, -1,
    1,  0,  3, 16, 11, 28, 12, 14,  6,  4,  2, -1, -1, -1, -1, -1
]
    
    /// Find the polynomial with value coefficients mod the generator as 30-bit.
public func bech32_polymod(_ values: Data) -> UInt32 {
        var chk: UInt32 = 1
        for v in values {
            let top = (chk >> 25)
            chk = (chk & 0x1ffffff) << 5 ^ UInt32(v)
            for i: UInt8 in 0..<5 {
                chk ^= ((top >> i) & 1) == 0 ? 0 : gen[Int(i)]
            }
        }
        return chk
    }


/// Expand a HRP for use in checksum computation.
func bech32_expand_hrp(_ s: String) -> Data {
    var left: [UInt8] = []
    var right: [UInt8] = []
    for x in Array(s) {
        let scalars = String(x).unicodeScalars
        left.append(UInt8(scalars[scalars.startIndex].value) >> 5)
        right.append(UInt8(scalars[scalars.startIndex].value) & 31)
    }
    return Data(left + [0] + right)
}
    
/// Verify checksum
public func bech32_verify(hrp: String, checksum: Data) -> Bool {
    var data = bech32_expand_hrp(hrp)
    data.append(checksum)
    return bech32_polymod(data) == 1
}
    
/// Create checksum
public func bech32_create_checksum(hrp: String, values: Data) -> Data {
    var enc = bech32_expand_hrp(hrp)
    enc.append(values)
    enc.append(Data(repeating: 0x00, count: 6))
    let mod: UInt32 = bech32_polymod(enc) ^ 1
    var ret: Data = Data(repeating: 0x00, count: 6)
    for i in 0..<6 {
        ret[i] = UInt8((mod >> (5 * (5 - i))) & 31)
    }
    return ret
}
    
public func bech32_encode(hrp: String, _ input: [UInt8]) -> String {
    let table: [Character] = Array("qpzry9x8gf2tvdw0s3jn54khce6mua7l")
    let bits = eightToFiveBits(input)
    let check_sum = bech32_checksum(hrp: hrp, data: bits)
    let separator = "1"
    return "\(hrp)" + separator + String((bits + check_sum).map { table[Int($0)] })
}

func bech32_checksum(hrp: String, data: [UInt8]) -> [UInt8] {
    let values = bech32_expand_hrp(hrp) + data
    let polymod = bech32_polymod(values + [0,0,0,0,0,0]) ^ 1
    var result: [UInt32] = []
    for i in (0..<6) {
        result.append((polymod >> (5 * (5 - UInt32(i)))) & 31)
    }
    return result.map { UInt8($0) }
}

func bech32_convert_bits(outbits: Int, input: Data, inbits: Int, pad: Int) -> Data? {
    let maxv: UInt32 = ((UInt32(1)) << outbits) - 1;
    var val: UInt32 = 0
    var bits: Int = 0
    var out = Data()
    
    for i in (0..<input.count) {
        val = (val << inbits) | UInt32(input[i])
        bits += inbits;
        while bits >= outbits {
            bits -= outbits;
            out.append(UInt8((val >> bits) & maxv))
        }
    }
    
    if pad != 0 {
        if bits != 0 {
            out.append(UInt8(val << (outbits - bits) & maxv))
        }
    } else if 0 != ((val << (outbits - bits)) & maxv) || bits >= inbits {
        return nil
    }
    
    return out
}

func eightToFiveBits(_ input: [UInt8]) -> [UInt8] {
    guard !input.isEmpty else { return [] }
    
    var outputSize = (input.count * 8) / 5
    if ((input.count * 8) % 5) != 0 {
        outputSize += 1
    }
    var outputArray: [UInt8] = []
    for i in (0..<outputSize) {
        let devision = (i * 5) / 8
        let reminder = (i * 5) % 8
        var element = input[devision] << reminder
        element >>= 3
        
        if (reminder > 3) && (i + 1 < outputSize) {
            element = element | (input[devision + 1] >> (8 - reminder + 3))
        }
        
        outputArray.append(element)
    }
    
    return outputArray
}
    
    /// Decode Bech32 string
public func bech32_decode(_ str: String) throws -> (hrp: String, data: Data)? {
    guard let strBytes = str.data(using: .utf8) else {
        throw Bech32Error.nonUTF8String
    }
    guard strBytes.count <= 90 else {
        throw Bech32Error.stringLengthExceeded
    }
    var lower: Bool = false
    var upper: Bool = false
    for c in strBytes {
        // printable range
        if c < 33 || c > 126 {
            throw Bech32Error.nonPrintableCharacter
        }
        // 'a' to 'z'
        if c >= 97 && c <= 122 {
            lower = true
        }
        // 'A' to 'Z'
        if c >= 65 && c <= 90 {
            upper = true
        }
    }
    if lower && upper {
        throw Bech32Error.invalidCase
    }
    guard let pos = str.range(of: checksumMarker, options: .backwards)?.lowerBound else {
        throw Bech32Error.noChecksumMarker
    }
    let intPos: Int = str.distance(from: str.startIndex, to: pos)
    guard intPos >= 1 else {
        throw Bech32Error.incorrectHrpSize
    }
    guard intPos + 7 <= str.count else {
        throw Bech32Error.incorrectChecksumSize
    }
    let vSize: Int = str.count - 1 - intPos
    var values: Data = Data(repeating: 0x00, count: vSize)
    for i in 0..<vSize {
        let c = strBytes[i + intPos + 1]
        let decInt = decCharset[Int(c)]
        if decInt == -1 {
            throw Bech32Error.invalidCharacter
        }
        values[i] = UInt8(decInt)
    }
    let hrp = String(str[..<pos]).lowercased()
    guard bech32_verify(hrp: hrp, checksum: values) else {
        throw Bech32Error.checksumMismatch
    }
    let out = Data(values[..<(vSize-6)])
    guard let converted = bech32_convert_bits(outbits: 8, input: out, inbits: 5, pad: 0) else {
        return nil
    }
    return (hrp, converted)
}

public enum Bech32Error: LocalizedError {
    case nonUTF8String
    case nonPrintableCharacter
    case invalidCase
    case noChecksumMarker
    case incorrectHrpSize
    case incorrectChecksumSize
    case stringLengthExceeded
    
    case invalidCharacter
    case checksumMismatch
    
    public var errorDescription: String? {
        switch self {
        case .checksumMismatch:
            return "Checksum doesn't match"
        case .incorrectChecksumSize:
            return "Checksum size too low"
        case .incorrectHrpSize:
            return "Human-readable-part is too small or empty"
        case .invalidCase:
            return "String contains mixed case characters"
        case .invalidCharacter:
            return "Invalid character met on decoding"
        case .noChecksumMarker:
            return "Checksum delimiter not found"
        case .nonPrintableCharacter:
            return "Non printable character in input string"
        case .nonUTF8String:
            return "String cannot be decoded by utf8 decoder"
        case .stringLengthExceeded:
            return "Input string is too long"
        }
    }
}
