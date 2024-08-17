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
    let owned: Bool
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

    init(note: UnsafeMutablePointer<ndb_note>, size: Int, owned: Bool, key: NoteKey?) {
        self.note = note
        self.owned = owned
        self.count = size
        self.key = key

        #if DEBUG_NOTE_SIZE
        if let owned_size {
            NdbNote.total_ndb_size += Int(owned_size)
            NdbNote.notes_created += 1

            print("\(NdbNote.notes_created) ndb_notes, \(NdbNote.total_ndb_size) bytes")
        }
        #endif

    }

    func to_owned() -> NdbNote {
        if self.owned {
            return self
        }

        let buf = malloc(self.count)!
        memcpy(buf, &self.note.pointee, self.count)
        let new_note = buf.assumingMemoryBound(to: ndb_note.self)

        return NdbNote(note: new_note, size: self.count, owned: true, key: self.key)
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

        return NdbNote(note: new_note, size: Int(len), owned: true, key: nil)
    }
    
    func get_inner_event() -> NdbNote? {
        return self.inner_event
    }
}

// Extension to make NdbNote compatible with NostrEvent's original API
extension NdbNote {
    var is_textlike: Bool {
        return kind == 1 || kind == 42 || kind == 30023 || kind == 9802
    }

    var is_quote_repost: NoteId? {
        guard kind == 1, let quoted_note_id = referenced_quote_ids.first else {
            return nil
        }
        return quoted_note_id.note_id
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

    public var referenced_mute_items: References<MuteItem> {
        References<MuteItem>(tags: self.tags)
    }
    
    public var referenced_comment_items: References<CommentItem> {
        References<CommentItem>(tags: self.tags)
    }

    public var references: References<RefId> {
        References<RefId>(tags: self.tags)
    }

    func thread_reply() -> ThreadReply? {
        if self.known_kind != .highlight {
            return ThreadReply(tags: self.tags)
        }
        return nil
    }
    
    func highlighted_note_id() -> NoteId? {
        return ThreadReply(tags: self.tags)?.reply.note_id
    }

    func get_content(_ keypair: Keypair) -> String {
        if known_kind == .dm {
            return decrypted(keypair: keypair) ?? "*failed to decrypt content*"
        }
        else if known_kind == .highlight {
            return self.referenced_comment_items.first?.content ?? ""
        }

        return content
    }

    func maybe_get_content(_ keypair: Keypair) -> String? {
        if known_kind == .dm {
            return decrypted(keypair: keypair)
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

    public func direct_replies() -> NoteId? {
        return thread_reply()?.reply.note_id
    }

    // NDBTODO: just use Id
    public func thread_id() -> NoteId {
        guard let root = self.thread_reply()?.root else {
            return self.id
        }

        return root.note_id
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

    func is_reply() -> Bool {
        return thread_reply() != nil
    }

    func note_language(_ keypair: Keypair) -> String? {
        assert(!Thread.isMainThread, "This function must not be run on the main thread.")

        // Rely on Apple's NLLanguageRecognizer to tell us which language it thinks the note is in
        // and filter on only the text portions of the content as URLs and hashtags confuse the language recognizer.
        let originalBlocks = self.blocks(keypair).blocks
        let originalOnlyText = originalBlocks.compactMap {
                if case .text(let txt) = $0 {
                    // Replacing right single quotation marks (’) with "typewriter or ASCII apostrophes" (')
                    // as a workaround to get Apple's language recognizer to predict language the correctly.
                    // It is important to add this workaround to get the language right because it wastes users' money to send translation requests.
                    // Until Apple fixes their language model, this workaround will be kept in place.
                    // See https://en.wikipedia.org/wiki/Apostrophe#Unicode for an explanation of the differences between the two characters.
                    //
                    // For example,
                    // "nevent1qqs0wsknetaju06xk39cv8sttd064amkykqalvfue7ydtg3p0lyfksqzyrhxagf6h8l9cjngatumrg60uq22v66qz979pm32v985ek54ndh8gj42wtp"
                    // has the note content "It’s a meme".
                    // Without the character replacement, it is 61% confident that the text is in Turkish (tr) and 8% confident that the text is in English (en),
                    // which is a wildly incorrect hypothesis.
                    // With the character replacement, it is 65% confident that the text is in English (en) and 24% confident that the text is in Turkish (tr), which is more accurate.
                    //
                    // Similarly,
                    // "nevent1qqspjqlln6wvxrqg6kzl2p7gk0rgr5stc7zz5sstl34cxlw55gvtylgpp4mhxue69uhkummn9ekx7mqpr4mhxue69uhkummnw3ez6ur4vgh8wetvd3hhyer9wghxuet5qy28wumn8ghj7un9d3shjtnwdaehgu3wvfnsygpx6655ve67vqlcme9ld7ww73pqx7msclhwzu8lqmkhvuluxnyc7yhf3xut"
                    // has the note content "You’re funner".
                    // Without the character replacement, it is 52% confident that the text is in Norwegian Bokmål (nb) and 41% confident that the text is in English (en).
                    // With the character replacement, it is 93% confident that the text is in English (en) and 4% confident that the text is in Norwegian Bokmål (nb).
                    return txt.replacingOccurrences(of: "’", with: "'")
                }
                else {
                    return nil
                }
            }
            .joined(separator: " ")

        // If there is no text, there's nothing to use to detect language.
        guard !originalOnlyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }

        let languageRecognizer = NLLanguageRecognizer()
        languageRecognizer.processString(originalOnlyText)

        // Only accept language recognition hypothesis if there's at least a 50% probability that it's accurate.
        guard let locale = languageRecognizer.languageHypotheses(withMaximum: 1).first(where: { $0.value >= 0.5 })?.key.rawValue else {
            return nil
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
