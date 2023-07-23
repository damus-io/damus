//
//  NdbNote.swift
//  damus
//
//  Created by William Casarin on 2023-07-21.
//

import Foundation

struct NdbNote {
    // we can have owned notes, but we can also have lmdb virtual-memory mapped notes so its optional
    private var owned: Data?
    let note: UnsafeMutablePointer<ndb_note>

    init(note: UnsafeMutablePointer<ndb_note>, data: Data?) {
        self.note = note
        self.owned = data
    }
    
    var owned_size: Int? {
        return owned?.count
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

    var id: Data {
        Data(buffer: UnsafeBufferPointer(start: ndb_note_id(note), count: 32))
    }
    
    var pubkey: Data {
        Data(buffer: UnsafeBufferPointer(start: ndb_note_pubkey(note), count: 32))
    }
    
    var created_at: UInt32 {
        ndb_note_created_at(note)
    }
    
    var kind: UInt32 {
        ndb_note_kind(note)
    }
    
    func tags() -> TagsSequence {
        return .init(note: self)
    }
    
    static func owned_from_json(json: String, bufsize: Int = 2 << 18) -> NdbNote? {
        var data = Data(capacity: bufsize)
        guard var json_cstr = json.cString(using: .utf8) else { return nil }
        
        var note: UnsafeMutablePointer<ndb_note>?
        
        let len = data.withUnsafeMutableBytes { (bytes: UnsafeMutableRawBufferPointer) in
            return ndb_note_from_json(&json_cstr, Int32(json_cstr.count), &note, bytes.baseAddress, Int32(bufsize))
        }
        
        guard let note else { return nil }
        
        // Create new Data with just the valid bytes
        let smol_data = Data(bytes: &note.pointee, count: Int(len))
        return NdbNote(note: note, data: smol_data)
    }
}


// NostrEvent compat
extension NdbNote {
    var is_textlike: Bool {
        return kind == 1 || kind == 42 || kind == 30023
    }

    var known_kind: NostrKind? {
        return NostrKind.init(rawValue: Int(kind))
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

    /*

    func get_inner_event(cache: EventCache) -> NostrEvent? {
        guard self.known_kind == .boost else {
            return nil
        }

        if self.content == "", let ref = self.referenced_ids.first {
            return cache.lookup(ref.ref_id)
        }

        return self.inner_event
    }

    func event_refs(_ privkey: String?) -> [EventRef] {
        if let rs = _event_refs {
            return rs
        }
        let refs = interpret_event_refs(blocks: self.blocks(privkey).blocks, tags: self.tags)
        self._event_refs = refs
        return refs
    }


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

        var pubkey = self.pubkey
        // This is our DM, we need to use the pubkey of the person we're talking to instead
        if our_pubkey == pubkey {
            guard let refkey = self.referenced_pubkeys.first else {
                return nil
            }

            pubkey = refkey.ref_id
        }

        let dec = decrypt_dm(key, pubkey: pubkey, content: self.content, encoding: .base64)
        self.decrypted_content = dec

        return dec
    }

    func get_content(_ privkey: String?) -> String {
        if known_kind == .dm {
            return decrypted(privkey: privkey) ?? "*failed to decrypt content*"
        }

        return content
    }

    var description: String {
        return "NostrEvent { id: \(id) pubkey \(pubkey) kind \(kind) tags \(tags) content '\(content)' }"
    }

    var known_kind: NostrKind? {
        return NostrKind.init(rawValue: kind)
    }

    private enum CodingKeys: String, CodingKey {
        case id, sig, tags, pubkey, created_at, kind, content
    }

    private func get_referenced_ids(key: String) -> [ReferencedId] {
        return damus.get_referenced_ids(tags: self.tags, key: key)
    }

    public func direct_replies(_ privkey: String?) -> [ReferencedId] {
        return event_refs(privkey).reduce(into: []) { acc, evref in
            if let direct_reply = evref.is_direct_reply {
                acc.append(direct_reply)
            }
        }
    }

    public func thread_id(privkey: String?) -> String {
        for ref in event_refs(privkey) {
            if let thread_id = ref.is_thread_id {
                return thread_id.ref_id
            }
        }

        return self.id
    }

    public func last_refid() -> ReferencedId? {
        var mlast: Int? = nil
        var i: Int = 0
        for tag in tags {
            if tag.count >= 2 && tag[0] == "e" {
                mlast = i
            }
            i += 1
        }

        guard let last = mlast else {
            return nil
        }

        return tag_to_refid(tags[last])
    }

    public func references(id: String, key: String) -> Bool {
        for tag in tags {
            if tag.count >= 2 && tag[0] == key {
                if tag[1] == id {
                    return true
                }
            }
        }

        return false
    }

    func is_reply(_ privkey: String?) -> Bool {
        return event_is_reply(self, privkey: privkey)
    }

    func note_language(_ privkey: String?) -> String? {
        // Rely on Apple's NLLanguageRecognizer to tell us which language it thinks the note is in
        // and filter on only the text portions of the content as URLs and hashtags confuse the language recognizer.
        let originalBlocks = blocks(privkey).blocks
        let originalOnlyText = originalBlocks.compactMap { $0.is_text }.joined(separator: " ")

        // Only accept language recognition hypothesis if there's at least a 50% probability that it's accurate.
        let languageRecognizer = NLLanguageRecognizer()
        languageRecognizer.processString(originalOnlyText)

        guard let locale = languageRecognizer.languageHypotheses(withMaximum: 1).first(where: { $0.value >= 0.5 })?.key.rawValue else {
            return nil
        }

        // Remove the variant component and just take the language part as translation services typically only supports the variant-less language.
        // Moreover, speakers of one variant can generally understand other variants.
        return localeToLanguage(locale)
    }

    public var referenced_ids: [ReferencedId] {
        return get_referenced_ids(key: "e")
    }

    public var referenced_pubkeys: [ReferencedId] {
        return get_referenced_ids(key: "p")
    }

    public var is_local: Bool {
        return (self.flags & 1) != 0
    }

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
