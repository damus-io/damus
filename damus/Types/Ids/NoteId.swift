//
//  NoteId.swift
//  damus
//
//  Created by William Casarin on 2023-07-28.
//

import Foundation

typealias NoteKey = UInt64

struct NoteId: IdType, TagKey, TagConvertible {
    let id: Data

    init(_ data: Data) {
        self.id = data
    }

    init?(hex: String) {
        guard let note_id = hex_decode_noteid(hex) else {
            return nil
        }
        self = note_id
    }

    var bech32: String {
        bech32_note_id(self)
    }

    /// Refer to this NoteId as a QuoteId
    var quote_id: QuoteId {
        QuoteId(self.id)
    }

    var keychar: AsciiCharacter { "e" }

    var tag: [String] {
        ["e", self.hex()]
    }

    static func from_tag(tag: TagSequence) -> NoteId? {
        var i = tag.makeIterator()

        guard tag.count >= 2,
              let t0 = i.next(),
              let key = t0.single_char,
              key == "e",
              let t1 = i.next(),
              let note_id = t1.id().map(NoteId.init)
        else { return nil }

        return note_id
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
