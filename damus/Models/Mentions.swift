//
//  Mentions.swift
//  damus
//
//  Created by William Casarin on 2022-05-04.
//

import Foundation

enum MentionType: AsciiCharacter, TagKey {
    case p
    case e
    case a
    case r

    var keychar: AsciiCharacter {
        self.rawValue
    }
}

enum MentionRef: TagKeys, TagConvertible, Equatable, Hashable {
    case pubkey(Pubkey)
    case note(NoteId)
    case nevent(NEvent)
    case nprofile(NProfile)
    case nrelay(String)
    case naddr(NAddr)

    var key: MentionType {
        switch self {
        case .pubkey: return .p
        case .note: return .e
        case .nevent: return .e
        case .nprofile: return .p
        case .nrelay: return .r
        case .naddr: return .a
        }
    }

    var bech32: String {
        return Bech32Object.encode(toBech32Object())
    }

    static func from_bech32(str: String) -> MentionRef? {
        switch Bech32Object.parse(str) {
        case .note(let noteid): return .note(noteid)
        case .npub(let pubkey): return .pubkey(pubkey)
        default: return nil
        }
    }

    var pubkey: Pubkey? {
        switch self {
        case .pubkey(let pubkey): return pubkey
        case .note:              return nil
        case .nevent(let nevent): return nevent.author
        case .nprofile(let nprofile): return nprofile.author
        case .nrelay: return nil
        case .naddr: return nil
        }
    }

    var tag: [String] {
        switch self {
        case .pubkey(let pubkey): return ["p", pubkey.hex()]
        case .note(let noteId):   return ["e", noteId.hex()]
        case .nevent(let nevent): return ["e", nevent.noteid.hex()]
        case .nprofile(let nprofile): return ["p", nprofile.author.hex()]
        case .nrelay(let url): return ["r", url]
        case .naddr(let naddr): return ["a", naddr.kind.description + ":" + naddr.author.hex() + ":" + naddr.identifier.string()]
        }
    }

    static func from_tag(tag: TagSequence) -> MentionRef? {
        guard tag.count >= 2 else { return nil }

        var i = tag.makeIterator()

        guard let t0 = i.next(),
              let chr = t0.single_char,
              let mention_type = MentionType(rawValue: chr),
              let element = i.next()
        else {
            return nil
        }

        switch mention_type {
        case .p:
            guard let data = element.id() else { return nil }
            return .pubkey(Pubkey(data))
        case .e:
            guard let data = element.id() else { return nil }
            return .note(NoteId(data))
        case .a:
            let str = element.string()
            let data = str.split(separator: ":")
            if(data.count != 3) { return nil }
            
            guard let pubkey = Pubkey(hex: String(data[1])) else { return nil }
            guard let kind = UInt32(data[0]) else { return nil }
            
            return .naddr(NAddr(identifier: String(data[2]), author: pubkey, relays: [], kind: kind))
        case .r: return .nrelay(element.string())
        }
    }
    
    func toBech32Object() -> Bech32Object {
        switch self {
        case .pubkey(let pk):
            return .npub(pk)
        case .note(let noteid):
            return .note(noteid)
        case .naddr(let naddr):
            return .naddr(naddr)
        case .nevent(let nevent):
            return .nevent(nevent)
        case .nprofile(let nprofile):
            return .nprofile(nprofile)
        case .nrelay(let url):
            return .nrelay(url)
        }
    }
}

struct Mention<T: Equatable>: Equatable {
    let index: Int?
    let ref: T

    static func any(_ mention_id: MentionRef, index: Int? = nil) -> Mention<MentionRef> {
        return Mention<MentionRef>(index: index, ref: mention_id)
    }

    static func noteref(_ id: NoteRef, index: Int? = nil) -> Mention<NoteRef> {
        return Mention<NoteRef>(index: index, ref: id)
    }

    static func note(_ id: NoteId, index: Int? = nil) -> Mention<NoteId> {
        return Mention<NoteId>(index: index, ref: id)
    }

    static func pubkey(_ pubkey: Pubkey, index: Int? = nil) -> Mention<Pubkey> {
        return Mention<Pubkey>(index: index, ref: pubkey)
    }
}

typealias Invoice = LightningInvoice<Amount>
typealias ZapInvoice = LightningInvoice<Int64>

enum InvoiceDescription {
    case description(String)
    case description_hash(Data)
}

struct LightningInvoice<T> {
    let description: InvoiceDescription
    let amount: T
    let string: String
    let expiry: UInt64
    let payment_hash: Data
    let created_at: UInt64
    
    var description_string: String {
        switch description {
        case .description(let string):
            return string
        case .description_hash:
            return ""
        }
    }
}

func maybe_pointee<T>(_ p: UnsafeMutablePointer<T>!) -> T? {
    guard p != nil else {
        return nil
    }
    return p.pointee
}

enum Amount: Equatable {
    case any
    case specific(Int64)
    
    func amount_sats_str() -> String {
        switch self {
        case .any:
            return NSLocalizedString("Any", comment: "Any amount of sats")
        case .specific(let amt):
            return format_msats(amt)
        }
    }
}

func format_msats_abbrev(_ msats: Int64) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.positiveSuffix = "m"
    formatter.positivePrefix = ""
    formatter.minimumFractionDigits = 0
    formatter.maximumFractionDigits = 3
    formatter.roundingMode = .down
    formatter.roundingIncrement = 0.1
    formatter.multiplier = 1
    
    let sats = NSNumber(value: (Double(msats) / 1000.0))
    
    if msats >= 1_000_000*1000 {
        formatter.positiveSuffix = "m"
        formatter.multiplier = 0.000001
    } else if msats >= 1000*1000 {
        formatter.positiveSuffix = "k"
        formatter.multiplier = 0.001
    } else {
        return sats.stringValue
    }
    
    return formatter.string(from: sats) ?? sats.stringValue
}

func format_msats(_ msat: Int64, locale: Locale = Locale.current) -> String {
    let numberFormatter = NumberFormatter()
    numberFormatter.numberStyle = .decimal
    numberFormatter.minimumFractionDigits = 0
    numberFormatter.maximumFractionDigits = 3
    numberFormatter.roundingMode = .down
    numberFormatter.locale = locale

    let sats = NSNumber(value: (Double(msat) / 1000.0))
    let formattedSats = numberFormatter.string(from: sats) ?? sats.stringValue

    let format = localizedStringFormat(key: "sats_count", locale: locale)
    return String(format: format, locale: locale, sats.decimalValue as NSDecimalNumber, formattedSats)
}

func convert_invoice_description(b11: bolt11) -> InvoiceDescription? {
    if let desc = b11.description {
        return .description(String(cString: desc))
    }
    
    if var deschash = maybe_pointee(b11.description_hash) {
        return .description_hash(Data(bytes: &deschash, count: 32))
    }
    
    return nil
}

func find_tag_ref(type: String, id: String, tags: [[String]]) -> Int? {
    var i: Int = 0
    for tag in tags {
        if tag.count >= 2 {
            if tag[0] == type && tag[1] == id {
                return i
            }
        }
        i += 1
    }
    
    return nil
}

struct PostTags {
    let blocks: [Block]
    let tags: [[String]]
}

/// Convert
func make_post_tags(post_blocks: [Block], tags: [[String]]) -> PostTags {
    var new_tags = tags

    for post_block in post_blocks {
        switch post_block {
        case .mention(let mention):
            switch(mention.ref) {
            case .note, .nevent:
                continue
            default:
                break
            }

            new_tags.append(mention.ref.tag)
        case .hashtag(let hashtag):
            new_tags.append(["t", hashtag.lowercased()])
        case .text: break
        case .invoice: break
        case .relay: break
        case .url(let url):
            new_tags.append(["r", url.absoluteString])
            break
        }
    }
    
    return PostTags(blocks: post_blocks, tags: new_tags)
}

func post_to_event(post: NostrPost, keypair: FullKeypair) -> NostrEvent? {
    let post_blocks = parse_post_blocks(content: post.content)
    let post_tags = make_post_tags(post_blocks: post_blocks, tags: post.tags)
    let content = post_tags.blocks
        .map(\.asString)
        .joined(separator: "")
    return NostrEvent(content: content, keypair: keypair.to_keypair(), kind: post.kind.rawValue, tags: post_tags.tags)
}
