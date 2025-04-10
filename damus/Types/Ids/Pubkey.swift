//
//  Pubkey.swift
//  damus
//
//  Created by William Casarin on 2023-07-28.
//

import Foundation

struct Pubkey: IdType, TagKey, TagConvertible, Identifiable {
    let id: Data

    var tag: [String] {
        [keychar.description, self.hex()]
    }

    init?(hex: String) {
        guard let id = hex_decode_pubkey(hex) else {
            return nil
        }
        self = id
    }

    init(_ data: Data) {
        self.id = data
    }

    var npub: String {
        bech32_pubkey(self)
    }

    var keychar: AsciiCharacter { "p" }

    static func from_tag(tag: TagSequence) -> Pubkey? {
        var i = tag.makeIterator()
        guard tag.count >= 2,
              let t0 = i.next(),
              let key = t0.single_char,
              key == "p",
              let t1 = i.next(),
              let pubkey = t1.id().map(Pubkey.init)
        else { return nil }

        return pubkey
    }
    
    func withUnsafePointer<T>(_ body: (UnsafePointer<UInt8>) throws -> T) rethrows -> T {
        return try self.id.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            guard let baseAddress = bytes.baseAddress else {
                fatalError("Cannot get base address")
            }
            return try baseAddress.withMemoryRebound(to: UInt8.self, capacity: bytes.count) { ptr in
                return try body(ptr)
            }
        }
    }
}

