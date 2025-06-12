//
//  NdbBlock.swift
//  damus
//
//  Created by William Casarin on 2024-01-25.
//

import Foundation

enum NdbBlockType: UInt32 {
    case hashtag = 1
    case text = 2
    case mention_index = 3
    case mention_bech32 = 4
    case url = 5
    case invoice = 6
}

extension ndb_mention_bech32_block {
    var bech32_type: NdbBech32Type? {
        NdbBech32Type(rawValue: self.bech32.type.rawValue)
    }
}

enum NdbBech32Type: UInt32 {
    case note = 1
    case npub = 2
    case nprofile = 3
    case nevent = 4
    case nrelay = 5
    case naddr = 6
    case nsec = 7

    var is_notelike: Bool {
        return self == .note || self == .nevent
    }
}

extension ndb_invoice_block {
    func as_invoice() -> Invoice? {
        let b11 = self.invoice
        let invstr = self.invstr.as_str()

        guard let description = convert_invoice_description(b11: b11) else {
            return nil
        }
        
        let amount: Amount = b11.amount == 0 ? .any : .specific(Int64(b11.amount))

        return Invoice(description: description, amount: amount, string: invstr, expiry: b11.expiry, created_at: b11.timestamp)
    }
}

enum NdbBlock {
    case text(ndb_str_block)
    case mention(ndb_mention_bech32_block)
    case hashtag(ndb_str_block)
    case url(ndb_str_block)
    case invoice(ndb_invoice_block)
    case mention_index(UInt32)

    init?(_ ptr: ndb_block_ptr) {
        guard let type = NdbBlockType(rawValue: ndb_get_block_type(ptr.ptr).rawValue) else {
            return nil
        }
        switch type {
        case .hashtag: self = .hashtag(ptr.block.str)
        case .text:    self = .text(ptr.block.str)
        case .invoice: self = .invoice(ptr.block.invoice)
        case .url:     self = .url(ptr.block.str)
        case .mention_bech32: self = .mention(ptr.block.mention_bech32)
        case .mention_index:  self = .mention_index(ptr.block.mention_index)
        }
    }
    
    var is_previewable: Bool {
        switch self {
        case .mention(let m):
            switch m.bech32_type {
            case .note, .nevent: return true
            default: return false
            }
        case .invoice:
            return true
        case .url:
            return true
        default:
            return false
        }
    }
    
    static func convertToStringCopy(from block: str_block_t) -> String? {
        guard let cString = block.str else {
            return nil
        }
        let byteBuffer = UnsafeBufferPointer(start: cString, count: Int(block.len)).map { UInt8(bitPattern: $0) }

        // Create a Swift String from the byte array
        return String(bytes: byteBuffer, encoding: .utf8)
    }
}


struct NdbBlocks {
    private let blocks_ptr: ndb_blocks_ptr

    init(ptr: OpaquePointer?) {
        self.blocks_ptr = ndb_blocks_ptr(ptr: ptr)
    }

    var words: Int {
        Int(ndb_blocks_word_count(blocks_ptr.ptr))
    }

    func iter(note: NdbNote) -> BlocksSequence {
        BlocksSequence(note: note, blocks: self)
    }

    func as_ptr() -> OpaquePointer? {
        return self.blocks_ptr.ptr
    }
}


