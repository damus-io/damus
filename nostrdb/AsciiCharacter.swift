//
//  AsciiCharacter.swift
//  damus
//
//  Created by William Casarin on 2023-07-21.
//

import Foundation

struct AsciiCharacter: ExpressibleByStringLiteral, CustomStringConvertible, Equatable, Hashable {
    private let value: UInt8

    var cchar: CChar {
        return CChar(bitPattern: value)
    }

    var description: String {
        return String(UnicodeScalar(UInt8(bitPattern: cchar)))
    }

    init?(_ cchar: CChar) {
        guard cchar < 127 else { return nil }
        self.value = UInt8(cchar)
    }

    init?(_ character: Character) {
        guard let asciiValue = character.asciiValue, asciiValue < 128 else {
            return nil
        }
        self.value = asciiValue
    }

    // MARK: - ExpressibleByStringLiteral conformance
    init(stringLiteral value: StringLiteralType) {
        guard value.count == 1, let character = value.first, let ascii = AsciiCharacter(character) else {
            fatalError("Invalid ASCII character initialization.")
        }
        self = ascii
    }

    var character: Character {
        return Character(UnicodeScalar(value))
    }
}
