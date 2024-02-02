//
//  Block.swift
//  damus
//

import Foundation


/// Represents a block of data stored in nostrdb. This can be
/// simple text, a hashtag, a url, a relay reference, a mention ref and
/// potentially more in the future.
enum Block: Equatable {
    static func == (lhs: Block, rhs: Block) -> Bool {
        switch (lhs, rhs) {
        case (.text(let a), .text(let b)):
            return a == b
        case (.mention(let a), .mention(let b)):
            return a == b
        case (.hashtag(let a), .hashtag(let b)):
            return a == b
        case (.url(let a), .url(let b)):
            return a == b
        case (.invoice(let a), .invoice(let b)):
            return a.string == b.string
        case (_, _):
            return false
        }
    }

    case text(String)
    case mention(Mention<MentionRef>)
    case hashtag(String)
    case url(URL)
    case invoice(Invoice)
    case relay(String)
}

struct Blocks: Equatable {
    let words: Int
    let blocks: [Block]
}

extension ndb_str_block {
    func as_str() -> String {
        let buf = UnsafeBufferPointer(start: self.str, count: Int(self.len))
        let uint8Buf = buf.map { UInt8(bitPattern: $0) }
        return String(decoding: uint8Buf, as: UTF8.self)
    }
}

extension ndb_block_ptr {
    func as_str() -> String {
        guard let str_block = ndb_block_str(self.ptr) else {
            return ""
        }
        return str_block.pointee.as_str()
    }

    var block: ndb_block.__Unnamed_union_block {
        self.ptr.pointee.block
    }
}

extension Block {
    /// Failable initializer for the C-backed type `block_t`. This initializer will inspect
    /// the underlying block type and build the appropriate enum value as needed.
    init?(block: ndb_block_ptr, tags: TagsSequence?) {
        switch ndb_get_block_type(block.ptr) {
        case BLOCK_HASHTAG:
            self = .hashtag(block.as_str())
        case BLOCK_TEXT:
            self = .text(block.as_str())
        case BLOCK_MENTION_INDEX:
            guard let b = Block(index: Int(block.block.mention_index), tags: tags) else {
                return nil
            }
            self = b
        case BLOCK_URL:
            guard let url = URL(string: block.as_str()) else { return nil }
            self = .url(url)
        case BLOCK_INVOICE:
            guard let b = Block(invoice: block.block.invoice) else { return nil }
            self = b
        case BLOCK_MENTION_BECH32:
            guard let b = Block(bech32: block.block.mention_bech32) else { return nil }
            self = b
        default:
            return nil
        }
    }
}
        
fileprivate extension Block {
    /// Failable initializer for a block index and a tag sequence.
    init?(index: Int, tags: TagsSequence? = nil) {
        guard let tags,
              index >= 0,
              index + 1 <= tags.count
        else {
            self = .text("#[\(index)]")
            return
        }
        
        let tag = tags[index]
        
        if let mention = MentionRef.from_tag(tag: tag) {
            self = .mention(.any(mention, index: index))
        }
        else {
            self = .text("#[\(index)]")
        }
    }
}

fileprivate extension Block {
    /// Failable initializer for the C-backed type `invoice_block_t`.
    init?(invoice: ndb_invoice_block) {
        guard let invoice = invoice.as_invoice() else { return nil }
        self = .invoice(invoice)
    }
}

fileprivate extension Block {
    /// Failable initializer for the C-backed type `mention_bech32_block_t`. This initializer will inspect the
    /// bech32 type code and build the appropriate enum type.
    init?(bech32 b: ndb_mention_bech32_block) {
        guard let decoded = decodeCBech32(b.bech32) else {
            return nil
        }
        guard let ref = decoded.toMentionRef() else {
            return nil
        }
        self = .mention(.any(ref))
    }
}

extension Block {
    var asString: String {
        switch self {
        case .mention(let m):
            if let idx = m.index {
                return "#[\(idx)]"
            }
            
            return "nostr:" + Bech32Object.encode(m.ref.toBech32Object())
        case .relay(let relay):
            return relay
        case .text(let txt):
            return txt
        case .hashtag(let htag):
            return "#" + htag
        case .url(let url):
            return url.absoluteString
        case .invoice(let inv):
            return inv.string
        }
    }
}
