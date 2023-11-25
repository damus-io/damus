//
//  NdbNote.swift
//  damus
//
//  Created by William Casarin on 2023-07-21.
//

import Foundation
import NaturalLanguage
import CommonCrypto
import secp256k1
import secp256k1_implementation
import CryptoKit

let MAX_NOTE_SIZE: Int = 2 << 18

struct NdbStr {
    let note: NdbNote
    let str: UnsafePointer<CChar>
}

struct NdbId {
    let note: NdbNote
    let id: Data
}

enum NdbData {
    case id(NdbId)
    case str(NdbStr)

    init(note: NdbNote, str: ndb_str) {
        guard str.flag == NDB_PACKED_ID else {
            self = .str(NdbStr(note: note, str: str.str))
            return
        }

        let buffer = UnsafeBufferPointer(start: str.id, count: 32)
        self = .id(NdbId(note: note, id: Data(buffer: buffer)))
    }
}

class NdbNote: Encodable, Equatable, Hashable {
    // we can have owned notes, but we can also have lmdb virtual-memory mapped notes so its optional
    private let owned: Bool
    let count: Int
    let key: NoteKey?
    let note: UnsafeMutablePointer<ndb_note>

    // cached stuff (TODO: remove these)
    var decrypted_content: String? = nil
    
    private var inner_event: NdbNote? {
        get {
            return NdbNote.owned_from_json_cstr(json: content_raw, json_len: content_len)
        }
    }

    init(note: UnsafeMutablePointer<ndb_note>, owned_size: Int?, key: NoteKey?) {
        self.note = note
        self.owned = owned_size != nil
        self.count = owned_size ?? 0
        self.key = key

        #if DEBUG_NOTE_SIZE
        if let owned_size {
            NdbNote.total_ndb_size += Int(owned_size)
            NdbNote.notes_created += 1

            print("\(NdbNote.notes_created) ndb_notes, \(NdbNote.total_ndb_size) bytes")
        }
        #endif

    }

    var content: String {
        String(cString: content_raw, encoding: .utf8) ?? ""
    }

    var content_raw: UnsafePointer<CChar> {
        ndb_note_content(note)
    }

    var content_len: UInt32 {
        ndb_note_content_length(note)
    }

    /// NDBTODO: make this into data
    var id: NoteId {
        .init(Data(bytes: ndb_note_id(note), count: 32))
    }

    var sig: Signature {
        .init(Data(bytes: ndb_note_sig(note), count: 64))
    }
    
    /// NDBTODO: make this into data
    var pubkey: Pubkey {
        .init(Data(bytes: ndb_note_pubkey(note), count: 32))
    }
    
    var created_at: UInt32 {
        ndb_note_created_at(note)
    }
    
    var kind: UInt32 {
        ndb_note_kind(note)
    }

    var tags: TagsSequence {
        .init(note: self)
    }

    deinit {
        if self.owned {
            #if DEBUG_NOTE_SIZE
            NdbNote.total_ndb_size -= Int(count)
            NdbNote.notes_created -= 1

            print("\(NdbNote.notes_created) ndb_notes, \(NdbNote.total_ndb_size) bytes")
            #endif
            free(note)
        }
    }

    static func == (lhs: NdbNote, rhs: NdbNote) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    private enum CodingKeys: String, CodingKey {
        case id, sig, tags, pubkey, created_at, kind, content
    }

    // Implement the `Encodable` protocol
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        try container.encode(hex_encode(id.id), forKey: .id)
        try container.encode(hex_encode(sig.data), forKey: .sig)
        try container.encode(pubkey, forKey: .pubkey)
        try container.encode(created_at, forKey: .created_at)
        try container.encode(kind, forKey: .kind)
        try container.encode(content, forKey: .content)
        try container.encode(tags, forKey: .tags)
    }

    #if DEBUG_NOTE_SIZE
    static var total_ndb_size: Int = 0
    static var notes_created: Int = 0
    #endif

    init?(content: String, keypair: Keypair, kind: UInt32 = 1, tags: [[String]] = [], createdAt: UInt32 = UInt32(Date().timeIntervalSince1970)) {

        var builder = ndb_builder()
        let buflen = MAX_NOTE_SIZE
        let buf = malloc(buflen)

        ndb_builder_init(&builder, buf, Int32(buflen))

        var pk_raw = keypair.pubkey.bytes

        ndb_builder_set_pubkey(&builder, &pk_raw)
        ndb_builder_set_kind(&builder, UInt32(kind))
        ndb_builder_set_created_at(&builder, UInt64(createdAt))

        var ok = true
        for tag in tags {
            ndb_builder_new_tag(&builder);
            for elem in tag {
                ok = elem.withCString({ eptr in
                    return ndb_builder_push_tag_str(&builder, eptr, Int32(elem.utf8.count)) > 0
                })
                if !ok {
                    return nil
                }
            }
        }

        ok = content.withCString { cptr in
            return ndb_builder_set_content(&builder, cptr, Int32(content.utf8.count)) > 0
        }
        if !ok {
            return nil
        }

        var n = UnsafeMutablePointer<ndb_note>?(nil)


        var the_kp: ndb_keypair? = nil

        if let sec = keypair.privkey {
            var kp = ndb_keypair()
            memcpy(&kp.secret.0, sec.id.bytes, 32);

            if ndb_create_keypair(&kp) <= 0 {
                print("bad keypair")
            } else {
                the_kp = kp
            }
        }

        var len: Int32 = 0
        if var the_kp {
            len = ndb_builder_finalize(&builder, &n, &the_kp)
        } else {
            len = ndb_builder_finalize(&builder, &n, nil)
        }

        if len <= 0 {
            free(buf)
            return nil
        }

        //guard let n else { return nil }

        self.owned = true
        self.count = Int(len)
        //self.note = n
        let r = realloc(buf, Int(len))
        guard let r else {
            free(buf)
            return nil
        }

        self.note = r.assumingMemoryBound(to: ndb_note.self)
        self.key = nil
    }

    static func owned_from_json(json: String, bufsize: Int = 2 << 18) -> NdbNote? {
        return json.withCString { cstr in
            return NdbNote.owned_from_json_cstr(
                json: cstr, json_len: UInt32(json.utf8.count), bufsize: bufsize)
        }
    }

    static func owned_from_json_cstr(json: UnsafePointer<CChar>, json_len: UInt32, bufsize: Int = 2 << 18) -> NdbNote? {
        let data = malloc(bufsize)
        //guard var json_cstr = json.cString(using: .utf8) else { return nil }

        //json_cs
        var note: UnsafeMutablePointer<ndb_note>?
        
        let len = ndb_note_from_json(json, Int32(json_len), &note, data, Int32(bufsize))

        if len == 0 {
            free(data)
            return nil
        }

        // Create new Data with just the valid bytes
        guard let note_data = realloc(data, Int(len)) else { return nil }
        let new_note = note_data.assumingMemoryBound(to: ndb_note.self)

        return NdbNote(note: new_note, owned_size: Int(len), key: nil)
    }
    
    func get_inner_event() -> NdbNote? {
        return self.inner_event
    }
}

// Extension to make NdbNote compatible with NostrEvent's original API
extension NdbNote {
    var is_textlike: Bool {
        return kind == 1 || kind == 42 || kind == 30023
    }

    var known_kind: NostrKind? {
        return NostrKind.init(rawValue: kind)
    }

    var too_big: Bool {
        return known_kind != .longform && self.content_len > 16000
    }

    var should_show_event: Bool {
        return !too_big
    }

    func get_blocks(keypair: Keypair) -> Blocks {
        return parse_note_content(content: .init(note: self, keypair: keypair))
    }

    // TODO: References iterator
    public var referenced_ids: References<NoteId> {
        References<NoteId>(tags: self.tags)
    }
    
    public var referenced_quote_ids: References<QuoteId> {
        References<QuoteId>(tags: self.tags)
    }

    public var referenced_noterefs: References<NoteRef> {
        References<NoteRef>(tags: self.tags)
    }

    public var referenced_follows: References<FollowRef> {
        References<FollowRef>(tags: self.tags)
    }

    public var referenced_pubkeys: References<Pubkey> {
        References<Pubkey>(tags: self.tags)
    }

    public var referenced_hashtags: References<Hashtag> {
        References<Hashtag>(tags: self.tags)
    }

    public var referenced_params: References<ReplaceableParam> {
        References<ReplaceableParam>(tags: self.tags)
    }

    public var references: References<RefId> {
        References<RefId>(tags: self.tags)
    }

    func event_refs(_ keypair: Keypair) -> [EventRef] {
        let refs = interpret_event_refs_ndb(blocks: self.blocks(keypair).blocks, tags: self.tags)
        return refs
    }

    func get_content(_ keypair: Keypair) -> String {
        if known_kind == .dm {
            return decrypted(keypair: keypair) ?? "*failed to decrypt content*"
        }

        return content
    }

    func blocks(_ keypair: Keypair) -> Blocks {
        return get_blocks(keypair: keypair)
    }

    // NDBTODO: switch this to operating on bytes not strings
    func decrypted(keypair: Keypair) -> String? {
        if let decrypted_content {
            return decrypted_content
        }

        let our_pubkey = keypair.pubkey

        // NDBTODO: don't hex encode
        var pubkey = self.pubkey
        // This is our DM, we need to use the pubkey of the person we're talking to instead

        if our_pubkey == pubkey, let pk = self.referenced_pubkeys.first {
            pubkey = pk
        }

        // NDBTODO: pass data to pubkey
        let dec = decrypt_dm(keypair.privkey, pubkey: pubkey, content: self.content, encoding: .base64)
        self.decrypted_content = dec

        return dec
    }

    public func direct_replies(_ keypair: Keypair) -> [NoteId] {
        return event_refs(keypair).reduce(into: []) { acc, evref in
            if let direct_reply = evref.is_direct_reply {
                acc.append(direct_reply.note_id)
            }
        }
    }

    // NDBTODO: just use Id
    public func thread_id(keypair: Keypair) -> NoteId {
        for ref in event_refs(keypair) {
            if let thread_id = ref.is_thread_id {
                return thread_id.note_id
            }
        }

        return self.id
    }

    public func last_refid() -> NoteId? {
        return self.referenced_ids.last
    }

    // NDBTODO: id -> data
    /*
    public func references(id: String, key: AsciiCharacter) -> Bool {
        var matcher: (Reference) -> Bool = { ref in ref.ref_id.matches_str(id) }
        if id.count == 64, let decoded = hex_decode(id) {
            matcher = { ref in ref.ref_id.matches_id(decoded) }
        }
        for ref in References(tags: self.tags) {
            if ref.key == key && matcher(ref) {
                return true
            }
        }

        return false
    }
     */

    func is_reply(_ keypair: Keypair) -> Bool {
        return event_is_reply(self.event_refs(keypair))
    }

    func note_language(_ keypair: Keypair) -> String? {
        assert(!Thread.isMainThread, "This function must not be run on the main thread.")

        // Rely on Apple's NLLanguageRecognizer to tell us which language it thinks the note is in
        // and filter on only the text portions of the content as URLs and hashtags confuse the language recognizer.
        let originalBlocks = self.blocks(keypair).blocks
        let originalOnlyText = originalBlocks.compactMap {
                if case .text(let txt) = $0 {
                    return txt
                }
                else {
                    return nil
                }
            }
            .joined(separator: " ")

        // Only accept language recognition hypothesis if there's at least a 50% probability that it's accurate.
        let languageRecognizer = NLLanguageRecognizer()
        languageRecognizer.processString(originalOnlyText)

        guard let locale = languageRecognizer.languageHypotheses(withMaximum: 1).first(where: { $0.value >= 0.5 })?.key.rawValue else {
            let nstr: String? = nil
            return nstr
        }

        // Remove the variant component and just take the language part as translation services typically only supports the variant-less language.
        // Moreover, speakers of one variant can generally understand other variants.
        return localeToLanguage(locale)
    }

    var age: TimeInterval {
        let event_date = Date(timeIntervalSince1970: TimeInterval(created_at))
        return Date.now.timeIntervalSince(event_date)
    }
}

func hex_encode(_ data: Data) -> String {
    var str = ""
    for c in data {
        let c1 = hexchar(c >> 4)
        let c2 = hexchar(c & 0xF)

        str.append(Character(Unicode.Scalar(c1)))
        str.append(Character(Unicode.Scalar(c2)))
    }
    return str
}
