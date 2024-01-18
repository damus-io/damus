//
//  Block.swift
//  damus
//
//  Created by Kyle Roucis on 2023-08-21.
//

import Foundation


fileprivate extension String {
    /// Failable initializer to build a Swift.String from a C-backed `str_block_t`.
    init?(_ s: str_block_t) {
        let len = s.end - s.start
        let bytes = Data(bytes: s.start, count: len)
        self.init(bytes: bytes, encoding: .utf8)
    }
}

/// Represents a block of data stored by the NOSTR protocol. This can be
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

extension Block {
    /// Failable initializer for the C-backed type `block_t`. This initializer will inspect
    /// the underlying block type and build the appropriate enum value as needed.
    init?(_ block: block_t, tags: TagsSequence? = nil) {
        switch block.type {
        case BLOCK_HASHTAG:
            guard let str = String(block.block.str) else {
                return nil
            }
            self = .hashtag(str)
        case BLOCK_TEXT:
            guard let str = String(block.block.str) else {
                return nil
            }
            self = .text(str)
        case BLOCK_MENTION_INDEX:
            guard let b = Block(index: Int(block.block.mention_index), tags: tags) else {
                return nil
            }
            self = b
        case BLOCK_URL:
            guard let b = Block(block.block.str) else {
                return nil
            }
            self = b
        case BLOCK_INVOICE:
            guard let b = Block(invoice: block.block.invoice) else {
                return nil
            }
            self = b
        case BLOCK_MENTION_BECH32:
            guard let b = Block(bech32: block.block.mention_bech32) else {
                return nil
            }
            self = b
        default:
            return nil
        }
    }
}
fileprivate extension Block {
    /// Failable initializer for the C-backed type `str_block_t`.
    init?(_ b: str_block_t) {
        guard let str = String(b) else {
            return nil
        }
        
        if let url = URL(string: str) {
            self = .url(url)
        }
        else {
            self = .text(str)
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
    init?(invoice: invoice_block_t) {
        guard let invstr = String(invoice.invstr) else {
            return nil
        }
        
        guard var b11 = maybe_pointee(invoice.bolt11) else {
            return nil
        }
        
        guard let description = convert_invoice_description(b11: b11) else {
            return nil
        }
        
        let amount: Amount = maybe_pointee(b11.msat).map { .specific(Int64($0.millisatoshis)) } ?? .any
        let payment_hash = Data(bytes: &b11.payment_hash, count: 32)
        let created_at = b11.timestamp
        
        tal_free(invoice.bolt11)
        self = .invoice(Invoice(description: description, amount: amount, string: invstr, expiry: b11.expiry, payment_hash: payment_hash, created_at: created_at))
    }
}

fileprivate extension Block {
    /// Failable initializer for the C-backed type `mention_bech32_block_t`. This initializer will inspect the
    /// bech32 type code and build the appropriate enum type.
    init?(bech32 b: mention_bech32_block_t) {
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
