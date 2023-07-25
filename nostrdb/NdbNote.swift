//
//  NdbNote.swift
//  damus
//
//  Created by William Casarin on 2023-07-21.
//

import Foundation
import NaturalLanguage


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

class NdbNote: Equatable, Hashable {
    // we can have owned notes, but we can also have lmdb virtual-memory mapped notes so its optional
    private let owned: Bool
    let count: Int
    let note: UnsafeMutablePointer<ndb_note>

    // cached stuff (TODO: remove these)
    private var _event_refs: [EventRef]? = nil
    var decrypted_content: String? = nil
    private var _blocks: Blocks? = nil
    private lazy var inner_event: NdbNote? = {
        return NdbNote.owned_from_json_cstr(json: content_raw, json_len: content_len)
    }()

    init(note: UnsafeMutablePointer<ndb_note>, owned_size: Int?) {
        self.note = note
        self.owned = owned_size != nil
        self.count = owned_size ?? 0
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
    var id: String {
        hex_encode(Data(buffer: UnsafeBufferPointer(start: ndb_note_id(note), count: 32)))
    }
    
    /// NDBTODO: make this into data
    var pubkey: String {
        hex_encode(Data(buffer: UnsafeBufferPointer(start: ndb_note_pubkey(note), count: 32)))
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
            free(note)
        }
    }

    static func == (lhs: NdbNote, rhs: NdbNote) -> Bool {
        return lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static let max_note_size: Int = 2 << 18

    init?(content: String, keypair: Keypair, kind: UInt32 = 1, tags: [[String]] = [], createdAt: UInt32 = UInt32(Date().timeIntervalSince1970)) {

        var builder = ndb_builder()
        let buflen = MAX_NOTE_SIZE
        let buf = malloc(buflen)
        let idbuf = malloc(buflen)

        ndb_builder_init(&builder, buf, Int32(buflen))

        guard var pk_raw = hex_decode(keypair.pubkey) else { return nil }

        ndb_builder_set_pubkey(&builder, &pk_raw)
        ndb_builder_set_kind(&builder, UInt32(kind))
        ndb_builder_set_created_at(&builder, createdAt)

        for tag in tags {
            ndb_builder_new_tag(&builder);
            for elem in tag {
                _ = elem.withCString { eptr in
                    ndb_builder_push_tag_str(&builder, eptr, Int32(elem.utf8.count))
                }
            }
        }

        _ = content.withCString { cptr in
            ndb_builder_set_content(&builder, content, Int32(content.utf8.count));
        }

        var n = UnsafeMutablePointer<ndb_note>?(nil)

        let keypair = keypair.privkey.map { sec in
            var kp = ndb_keypair()
            return sec.withCString { secptr in
                ndb_decode_key(secptr, &kp)
                return kp
            }
        }

        var len: Int32 = 0
        if var keypair {
            len = ndb_builder_finalize(&builder, &n, &keypair)
        } else {
            len = ndb_builder_finalize(&builder, &n, nil)
        }

        free(idbuf)

        self.owned = true
        self.count = Int(len)
        self.note = realloc(n, Int(len)).assumingMemoryBound(to: ndb_note.self)
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

        return NdbNote(note: new_note, owned_size: Int(len))
    }
}


// NostrEvent compat
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

    
    //var is_valid_id: Bool {
     //   return calculate_event_id(ev: self) == self.id
    //}

    func get_blocks(content: String) -> Blocks {
        return parse_note_content_ndb(note: self)
    }

    func get_inner_event(cache: EventCache) -> NostrEvent? {
        guard self.known_kind == .boost else {
            return nil
        }

        if self.content == "", let ref = self.referenced_ids.first {
            // TODO: raw id cache lookups
            let id = ref.id.string()
            return cache.lookup(id)
        }

        // TODO: how to handle inner events?
        return nil
        //return self.inner_event
    }

    // TODO: References iterator
    public var referenced_ids: LazyFilterSequence<References> {
        References.ids(tags: self.tags)
    }

    public var referenced_pubkeys: LazyFilterSequence<References> {
        References.pubkeys(tags: self.tags)
    }

    public var referenced_hashtags: LazyFilterSequence<References> {
        References.hashtags(tags: self.tags)
    }

    func event_refs(_ privkey: String?) -> [EventRef] {
        if let rs = _event_refs {
            return rs
        }
        let refs = interpret_event_refs_ndb(blocks: self.blocks(privkey).blocks, tags: self.tags)
        self._event_refs = refs
        return refs
    }

    func get_content(_ privkey: String?) -> String {
        if known_kind == .dm {
            return decrypted(privkey: privkey) ?? "*failed to decrypt content*"
        }

        return content
    }

    func blocks(_ privkey: String?) -> Blocks {
        if let bs = _blocks { return bs }

        let blocks = get_blocks(content: self.get_content(privkey))
        self._blocks = blocks
        return blocks
    }

    // NDBTODO: switch this to operating on bytes not strings
    func decrypted(privkey: String?) -> String? {
        if let decrypted_content = decrypted_content {
            return decrypted_content
        }

        guard let key = privkey else {
            return nil
        }

        guard let our_pubkey = privkey_to_pubkey(privkey: key) else {
            return nil
        }

        // NDBTODO: don't hex encode
        var pubkey = self.pubkey
        // This is our DM, we need to use the pubkey of the person we're talking to instead

        if our_pubkey == pubkey {
            guard let refkey = self.referenced_pubkeys.first else {
                return nil
            }

            pubkey = refkey.ref_id.string()
        }

        // NDBTODO: pass data to pubkey
        let dec = decrypt_dm(key, pubkey: pubkey, content: self.content, encoding: .base64)
        self.decrypted_content = dec

        return dec
    }

    /*

    var description: String {
        return "NostrEvent { id: \(id) pubkey \(pubkey) kind \(kind) tags \(tags) content '\(content)' }"
    }

    // Not sure I should implement this
    private func get_referenced_ids(key: String) -> [ReferencedId] {
        return damus.get_referenced_ids(tags: self.tags, key: key)
    }
     */

    public func direct_replies(_ privkey: String?) -> [ReferencedId] {
        return event_refs(privkey).reduce(into: []) { acc, evref in
            if let direct_reply = evref.is_direct_reply {
                acc.append(direct_reply)
            }
        }
    }

    // NDBTODO: just use Id
    public func thread_id(privkey: String?) -> String {
        for ref in event_refs(privkey) {
            if let thread_id = ref.is_thread_id {
                return thread_id.ref_id
            }
        }

        return self.id
    }

    public func last_refid() -> ReferencedId? {
        return self.referenced_ids.last?.to_referenced_id()
    }

    // NDBTODO: id -> data
    public func references(id: String, key: AsciiCharacter) -> Bool {
        for ref in References(tags: self.tags) {
            if ref.key == key && ref.id.string() == id {
                return true
            }
        }

        return false
    }

    func is_reply(_ privkey: String?) -> Bool {
        return event_is_reply(self.event_refs(privkey))
    }

    func note_language(_ privkey: String?) async -> String? {
        let t = Task.detached {
            // Rely on Apple's NLLanguageRecognizer to tell us which language it thinks the note is in
            // and filter on only the text portions of the content as URLs and hashtags confuse the language recognizer.
            let originalBlocks = self.blocks(privkey).blocks
            let originalOnlyText = originalBlocks.compactMap { $0.is_text }.joined(separator: " ")

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

        return await t.value
    }

    /*

    func calculate_id() {
        self.id = calculate_event_id(ev: self)
    }

    func sign(privkey: String) {
        self.sig = sign_event(privkey: privkey, ev: self)
    }

    var age: TimeInterval {
        let event_date = Date(timeIntervalSince1970: TimeInterval(created_at))
        return Date.now.timeIntervalSince(event_date)
    }
     */
}

extension LazyFilterSequence {
    var first: Element? {
        self.first(where: { _ in true })
    }

    var last: Element? {
        var ev: Element? = nil
        for e in self {
            ev = e
        }
        return ev
    }
}
