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

    var keychar: AsciiCharacter {
        self.rawValue
    }
}

enum MentionRef: TagKeys, TagConvertible, Equatable, Hashable {
    case pubkey(Pubkey) // TODO: handle nprofile
    case note(NoteId)

    var key: MentionType {
        switch self {
        case .pubkey: return .p
        case .note: return .e
        }
    }

    var bech32: String {
        switch self {
        case .pubkey(let pubkey): return bech32_pubkey(pubkey)
        case .note(let noteId):   return bech32_note_id(noteId)
        }
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
        }
    }

    var tag: [String] {
        switch self {
        case .pubkey(let pubkey): return ["p", pubkey.hex()]
        case .note(let noteId):   return ["e", noteId.hex()]
        }
    }

    static func from_tag(tag: TagSequence) -> MentionRef? {
        guard tag.count >= 2 else { return nil }

        var i = tag.makeIterator()

        guard let t0 = i.next(),
              let chr = t0.single_char,
              let mention_type = MentionType(rawValue: chr),
              let id = i.next()?.id()
        else {
            return nil
        }

        switch mention_type {
        case .p: return .pubkey(Pubkey(id))
        case .e: return .note(NoteId(id))
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
    
    var is_invoice: Invoice? {
        if case .invoice(let invoice) = self {
            return invoice
        }
        return nil
    }
    
    var is_hashtag: String? {
        if case .hashtag(let htag) = self {
            return htag
        }
        return nil
    }
    
    var is_url: URL? {
        if case .url(let url) = self {
            return url
        }
        
        return nil
    }
    
    var is_text: String? {
        if case .text(let txt) = self {
            return txt
        }
        return nil
    }
    
    var is_note_mention: Bool {
        if case .mention(let mention) = self,
           case .note = mention.ref {
            return true
        }
        return false
    }

    var is_mention: Mention<MentionRef>? {
        if case .mention(let m) = self {
            return m
        }
        return nil
    }
}

func render_blocks(blocks: [Block]) -> String {
    return blocks.reduce("") { str, block in
        switch block {
        case .mention(let m):
            if let idx = m.index {
                return str + "#[\(idx)]"
            }

            switch m.ref {
            case .pubkey(let pk):    return str + "nostr:\(pk.npub)"
            case .note(let note_id): return str + "nostr:\(note_id.bech32)"
            }
        case .relay(let relay):
            return str + relay
        case .text(let txt):
            return str + txt
        case .hashtag(let htag):
            return str + "#" + htag
        case .url(let url):
            return str + url.absoluteString
        case .invoice(let inv):
            return str + inv.string
        }
    }
}

struct Blocks: Equatable {
    let words: Int
    let blocks: [Block]
}

func strblock_to_string(_ s: str_block_t) -> String? {
    let len = s.end - s.start
    let bytes = Data(bytes: s.start, count: len)
    return String(bytes: bytes, encoding: .utf8)
}

func convert_block(_ b: block_t, tags: TagsSequence?) -> Block? {
    if b.type == BLOCK_HASHTAG {
        guard let str = strblock_to_string(b.block.str) else {
            return nil
        }
        return .hashtag(str)
    } else if b.type == BLOCK_TEXT {
        guard let str = strblock_to_string(b.block.str) else {
            return nil
        }
        return .text(str)
    } else if b.type == BLOCK_MENTION_INDEX {
        return convert_mention_index_block(ind: Int(b.block.mention_index), tags: tags)
    } else if b.type == BLOCK_URL {
        return convert_url_block(b.block.str)
    } else if b.type == BLOCK_INVOICE {
        return convert_invoice_block(b.block.invoice)
    } else if b.type == BLOCK_MENTION_BECH32 {
        return convert_mention_bech32_block(b.block.mention_bech32)
    }

    return nil
}

func convert_url_block(_ b: str_block) -> Block? {
    guard let str = strblock_to_string(b) else {
        return nil
    }
    guard let url = URL(string: str) else {
        return .text(str)
    }
    return .url(url)
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

func convert_invoice_block(_ b: invoice_block) -> Block? {
    guard let invstr = strblock_to_string(b.invstr) else {
        return nil
    }
    
    guard var b11 = maybe_pointee(b.bolt11) else {
        return nil
    }
    
    guard let description = convert_invoice_description(b11: b11) else {
        return nil
    }
    
    let amount: Amount = maybe_pointee(b11.msat).map { .specific(Int64($0.millisatoshis)) } ?? .any
    let payment_hash = Data(bytes: &b11.payment_hash, count: 32)
    let created_at = b11.timestamp
    
    tal_free(b.bolt11)
    return .invoice(Invoice(description: description, amount: amount, string: invstr, expiry: b11.expiry, payment_hash: payment_hash, created_at: created_at))
}

func convert_mention_bech32_block(_ b: mention_bech32_block) -> Block?
{
    switch b.bech32.type {
    case NOSTR_BECH32_NOTE:
        let note = b.bech32.data.note;
        let note_id = NoteId(Data(bytes: note.event_id, count: 32))
        return .mention(.any(.note(note_id)))

    case NOSTR_BECH32_NEVENT:
        let nevent = b.bech32.data.nevent;
        let note_id = NoteId(Data(bytes: nevent.event_id, count: 32))
        return .mention(.any(.note(note_id)))

    case NOSTR_BECH32_NPUB:
        let npub = b.bech32.data.npub
        let pubkey = Pubkey(Data(bytes: npub.pubkey, count: 32))
        return .mention(.any(.pubkey(pubkey)))

    case NOSTR_BECH32_NSEC:
        let nsec = b.bech32.data.nsec
        let privkey = Privkey(Data(bytes: nsec.nsec, count: 32))
        guard let pubkey = privkey_to_pubkey(privkey: privkey) else { return nil }
        return .mention(.any(.pubkey(pubkey)))

    case NOSTR_BECH32_NPROFILE:
        let nprofile = b.bech32.data.nprofile
        let pubkey = Pubkey(Data(bytes: nprofile.pubkey, count: 32))
        return .mention(.any(.pubkey(pubkey)))

    case NOSTR_BECH32_NRELAY:
        let nrelay = b.bech32.data.nrelay
        guard let relay_str = strblock_to_string(nrelay.relay) else {
            return nil
        }
        return .relay(relay_str)
        
    case NOSTR_BECH32_NADDR:
        // TODO: wtf do I do with this
        guard let naddr = strblock_to_string(b.str) else {
            return nil
        }
        return .text("nostr:" + naddr)

    default:
        return nil
    }
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

func convert_mention_index_block(ind: Int, tags: TagsSequence?) -> Block?
{
    guard let tags,
          ind >= 0,
          ind + 1 <= tags.count
    else {
        return .text("#[\(ind)]")
    }

    let tag = tags[ind]

    guard let mention = MentionRef.from_tag(tag: tag) else {
        return .text("#[\(ind)]")
    }

    return .mention(.any(mention, index: ind))
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
            if case .note = mention.ref {
                continue
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
    let tags = post.references.map({ r in r.tag }) + post.tags
    let post_blocks = parse_post_blocks(content: post.content)
    let post_tags = make_post_tags(post_blocks: post_blocks, tags: tags)
    let content = render_blocks(blocks: post_tags.blocks)
    return NostrEvent(content: content, keypair: keypair.to_keypair(), kind: post.kind.rawValue, tags: post_tags.tags)
}

